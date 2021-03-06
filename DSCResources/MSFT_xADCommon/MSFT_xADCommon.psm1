$script:resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:modulesFolderPath = Join-Path -Path $script:resourceModulePath -ChildPath 'Modules'

$script:localizationModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'xActiveDirectory.Common'
Import-Module -Name (Join-Path -Path $script:localizationModulePath -ChildPath 'xActiveDirectory.Common.psm1')

data localizedString
{
    # culture="en-US"
    ConvertFrom-StringData @'
        WasExpectingDomainController     = The operating system product type code returned 2, which indicates that this is domain controller, but was unable to retrieve the domain controller object. (ADCOMMON0001)
        FailedEvaluatingDomainController = Could not evaluate if the node is a domain controller. (ADCOMMON0002)
        EvaluatePropertyState            = Evaluating the state of the property '{0}'. (ADCOMMON0003)
        PropertyInDesiredState           = The parameter '{0}' is in desired state. (ADCOMMON0004)
        PropertyNotInDesiredState        = The parameter '{0}' is not in desired state. (ADCOMMON0005)
        ArrayDoesNotMatch                = One or more values in an array does not match the desired state. Details of the changes are below. (ADCOMMON0006)
        ArrayValueThatDoesNotMatch       = {0} - {1} (ADCOMMON0007)
        PropertyValueOfTypeDoesNotMatch  = {0} value does not match. Current value is '{1}', but expected the value '{2}'. (ADCOMMON0008)
        UnableToCompareType              = Unable to compare the type {0} as it is not handled by the Test-DscPropertyState cmdlet. (ADCOMMON0009)
        RoleNotFoundError                = Please ensure that the PowerShell module for role '{0}' is installed. (ADCOMMON0010)
        MembersAndIncludeExcludeError    = The '{0}' and '{1}' and/or '{2}' parameters conflict. The '{0}' parameter should not be used in any combination with the '{1}' and '{2}' parameters. (ADCOMMON0011)
        MembersIsNullError               = The Members parameter value is null. The '{0}' parameter must be provided if neither '{1}' nor '{2}' is provided. (ADCOMMON0012)
        MembersIsEmptyError              = The Members parameter is empty.  At least one group member must be provided. (ADCOMMON0013)
        IncludeAndExcludeConflictError   = The member '{0}' is included in both '{1}' and '{2}' parameter values. The same member must not be included in both '{1}' and '{2}' parameter values. (ADCOMMON0014)
        IncludeAndExcludeAreEmptyError   = The '{0}' and '{1}' parameters are either both null or empty.  At least one member must be specified in one of these parameters. (ADCOMMON0015)
        ModeConversionError              = Converted mode {0} is not a {1}. (ADCOMMON0016)
        RecycleBinRestoreFailed          = Restoring {0} ({1}) from the recycle bin failed. Error message: {2}. (ADCOMMON0017)
        EmptyDomainError                 = No domain name retrieved for group member {0} in group {1}. (ADCOMMON0018)
        CheckingMembers                  = Checking for '{0}' members. (ADCOMMON0019)
        MembershipCountMismatch          = Membership count is not correct. Expected '{0}' members, actual '{1}' members. (ADCOMMON0020)
        MemberNotInDesiredState          = Member '{0}' is not in the desired state. (ADCOMMON0021)
        RemovingDuplicateMember          = Removing duplicate member '{0}' definition. (ADCOMMON0022)
        MembershipInDesiredState         = Membership is in the desired state. (ADCOMMON0023)
        MembershipNotDesiredState        = Membership is NOT in the desired state. (ADCOMMON0024)
        CheckingDomain                   = Checking for domain '{0}'. (ADCOMMON0025)
        CheckingSite                     = Checking for site '{0}'. (ADCOMMON0026)
        FindInRecycleBin                 = Finding objects in the recycle bin matching the filter {0}. (ADCOMMON0027)
        FoundRestoreTargetInRecycleBin   = Found object {0} ({1}) in the recycle bin as {2}. Attempting to restore the object. (ADCOMMON0028)
        RecycleBinRestoreSuccessful      = Successfully restored object {0} ({1}) from the recycle bin. (ADCOMMON0029)
        AddingGroupMember                = Adding member '{0}' from domain '{1}' to AD group '{2}'. (ADCOMMON0030)
        PropertyMapArrayIsWrongType      = An object in the property map array is not of the type [System.Collections.Hashtable]. (ADCOMMON0031)
'@
}

# Internal function to assert if the role specific module is installed or not
function Assert-Module
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ModuleName = 'ActiveDirectory',

        [Parameter()]
        [switch]
        $ImportModule
    )

    if (-not (Get-Module -Name $ModuleName -ListAvailable))
    {
        $errorId = '{0}_ModuleNotFound' -f $ModuleName;
        $errorMessage = $localizedString.RoleNotFoundError -f $moduleName;
        ThrowInvalidOperationError -ErrorId $errorId -ErrorMessage $errorMessage;
    }

    if ($ImportModule)
    {
        Import-Module -Name $ModuleName
    }
} #end function Assert-Module

# Internal function to test whether computer is a member of a domain
function Test-DomainMember
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
    )

    $isDomainMember = [System.Boolean] (Get-CimInstance -ClassName Win32_ComputerSystem -Verbose:$false).PartOfDomain;
    return $isDomainMember;
}


# Internal function to get the domain name of the computer
function Get-DomainName
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
    )

    $domainName = [System.String] (Get-CimInstance -ClassName Win32_ComputerSystem -Verbose:$false).Domain;
    return $domainName;
} # function Get-DomainName

# Internal function to build domain FQDN
function Resolve-DomainFQDN
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [OutputType([System.String])]
        [System.String] $DomainName,

        [Parameter()] [AllowNull()]
        [System.String] $ParentDomainName
    )

    $domainFQDN = $DomainName
    if ($ParentDomainName)
    {
        $domainFQDN = '{0}.{1}' -f $DomainName, $ParentDomainName;
    }
    return $domainFQDN
}

## Internal function to test/ domain availability
function Test-ADDomain
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String] $DomainName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.CredentialAttribute()]
        $Credential
    )

    Write-Verbose -Message ($localizedString.CheckingDomain -f $DomainName);
    $ldapDomain = 'LDAP://{0}' -f $DomainName;
    if ($PSBoundParameters.ContainsKey('Credential'))
    {
        $domain = New-Object DirectoryServices.DirectoryEntry($ldapDomain, $Credential.UserName, $Credential.GetNetworkCredential().Password);
    }
    else
    {
        $domain = New-Object DirectoryServices.DirectoryEntry($ldapDomain);
    }
    return ($null -ne $domain);
}

# Internal function to get an Active Directory object's parent Distinguished Name
function Get-ADObjectParentDN
{
    <#
        Copyright (c) 2016 The University Of Vermont
        All rights reserved.

        Redistribution and use in source and binary forms, with or without modification, are permitted provided that
        the following conditions are met:

        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the
           following disclaimer.
        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
           following disclaimer in the documentation and/or other materials provided with the distribution.
        3. Neither the name of the University nor the names of its contributors may be used to endorse or promote
           products derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
        LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
        IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
        CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
        OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
        CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
        THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

        http://www.uvm.edu/~gcd/code-license/
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DN
    )

    # https://www.uvm.edu/~gcd/2012/07/listing-parent-of-ad-object-in-powershell/
    $distinguishedNameParts = $DN -split '(?<![\\]),';
    $distinguishedNameParts[1..$($distinguishedNameParts.Count - 1)] -join ',';

} #end function GetADObjectParentDN

# Internal function that validates the Members, MembersToInclude and MembersToExclude combination
# is valid. If the combination is invalid, an InvalidArgumentError is raised.
function Assert-MemberParameters
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [ValidateNotNull()]
        [System.String[]]
        $Members,

        [Parameter()]
        [ValidateNotNull()]
        [System.String[]]
        $MembersToInclude,

        [Parameter()]
        [ValidateNotNull()]
        [System.String[]]
        $MembersToExclude,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ModuleName = 'xActiveDirectory'
    )

    if ($PSBoundParameters.ContainsKey('Members'))
    {
        if ($PSBoundParameters.ContainsKey('MembersToInclude') -or $PSBoundParameters.ContainsKey('MembersToExclude'))
        {
            # If Members are provided, Include and Exclude are not allowed.
            $errorId = '{0}_MembersPlusIncludeOrExcludeConflict' -f $ModuleName;
            $errorMessage = $localizedString.MembersAndIncludeExcludeError -f 'Members', 'MembersToInclude', 'MembersToExclude';
            ThrowInvalidArgumentError -ErrorId $errorId -ErrorMessage $errorMessage;
        }

        if ($Members.Length -eq 0) # )
        {
            $errorId = '{0}_MembersIsNull' -f $ModuleName;
            $errorMessage = $localizedString.MembersIsNullError -f 'Members', 'MembersToInclude', 'MembersToExclude';
            ThrowInvalidArgumentError -ErrorId $errorId -ErrorMessage $errorMessage;
        }
    }

    if ($PSBoundParameters.ContainsKey('MembersToInclude'))
    {
        $MembersToInclude = [System.String[]] @(Remove-DuplicateMembers -Members $MembersToInclude);
    }

    if ($PSBoundParameters.ContainsKey('MembersToExclude'))
    {
        $MembersToExclude = [System.String[]] @(Remove-DuplicateMembers -Members $MembersToExclude);
    }

    if (($PSBoundParameters.ContainsKey('MembersToInclude')) -and ($PSBoundParameters.ContainsKey('MembersToExclude')))
    {
        if (($MembersToInclude.Length -eq 0) -and ($MembersToExclude.Length -eq 0))
        {
            $errorId = '{0}_EmptyIncludeAndExclude' -f $ModuleName;
            $errorMessage = $localizedString.IncludeAndExcludeAreEmptyError -f 'MembersToInclude', 'MembersToExclude';
            ThrowInvalidArgumentError -ErrorId $errorId -ErrorMessage $errorMessage;
        }

        # Both MembersToInclude and MembersToExlude were provided. Check if they have common principals.
        foreach ($member in $MembersToInclude)
        {
            if ($member -in $MembersToExclude)
            {
                $errorId = '{0}_IncludeAndExcludeConflict' -f $ModuleName;
                $errorMessage = $localizedString.IncludeAndExcludeConflictError -f $member, 'MembersToInclude', 'MembersToExclude';
                ThrowInvalidArgumentError -ErrorId $errorId -ErrorMessage $errorMessage;
            }
        }
    }

} #end function Assert-MemberParameters

## Internal function to remove duplicate strings (members) from a string array
function Remove-DuplicateMembers
{
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        $Members
    )

    Set-StrictMode -Version Latest

    $destIndex = 0;
    for ([int] $sourceIndex = 0 ; $sourceIndex -lt $Members.Count; $sourceIndex++)
    {
        $matchFound = $false;
        for ([int] $matchIndex = 0; $matchIndex -lt $destIndex; $matchIndex++)
        {
            if ($Members[$sourceIndex] -eq $Members[$matchIndex])
            {
                # A duplicate is found. Discard the duplicate.
                Write-Verbose -Message ($localizedString.RemovingDuplicateMember -f $Members[$sourceIndex]);
                $matchFound = $true;
                continue;
            }
        }

        if (!$matchFound)
        {
            $Members[$destIndex++] = $Members[$sourceIndex].ToLowerInvariant();
        }
    }

    # Create the output array.
    $destination = New-Object -TypeName System.String[] -ArgumentList $destIndex;

    # Copy only distinct elements from the original array to the destination array.
    [System.Array]::Copy($Members, $destination, $destIndex);

    return $destination;

} #end function RemoveDuplicateMembers

# Internal function to test whether the existing array members match the defined explicit array
# members, the included members are present and the exlcuded members are not present.
function Test-Members
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        ## Existing array members
        [Parameter()]
        [AllowNull()]
        [System.String[]]
        $ExistingMembers,

        ## Explicit array members
        [Parameter()]
        [AllowNull()]
        [System.String[]]
        $Members,

        ## Compulsory array members
        [Parameter()]
        [AllowNull()]
        [System.String[]]
        $MembersToInclude,

        ## Excluded array members
        [Parameter()]
        [AllowNull()]
        [System.String[]]
        $MembersToExclude
    )

    if ($PSBoundParameters.ContainsKey('Members'))
    {
        if ($null -eq $Members -or (($Members.Count -eq 1) -and ($Members[0].Length -eq 0)))
        {
            $Members = @();
        }
        Write-Verbose ($localizedString.CheckingMembers -f 'Explicit');
        $Members = [System.String[]] @(Remove-DuplicateMembers -Members $Members);
        if ($ExistingMembers.Count -ne $Members.Count)
        {
            Write-Verbose -Message ($localizedString.MembershipCountMismatch -f $Members.Count, $ExistingMembers.Count);
            return $false;
        }

        foreach ($member in $Members)
        {
            if ($member -notin $ExistingMembers)
            {
                Write-Verbose -Message ($localizedString.MemberNotInDesiredState -f $member);
                return $false;
            }
        }
    } #end if $Members

    if ($PSBoundParameters.ContainsKey('MembersToInclude'))
    {
        if ($null -eq $MembersToInclude -or (($MembersToInclude.Count -eq 1) -and ($MembersToInclude[0].Length -eq 0)))
        {
            $MembersToInclude = @();
        }
        Write-Verbose -Message ($localizedString.CheckingMembers -f 'Included');
        $MembersToInclude = [System.String[]] @(Remove-DuplicateMembers -Members $MembersToInclude);
        foreach ($member in $MembersToInclude)
        {
            if ($member -notin $ExistingMembers)
            {
                Write-Verbose -Message ($localizedString.MemberNotInDesiredState -f $member);
                return $false;
            }
        }
    } #end if $MembersToInclude

    if ($PSBoundParameters.ContainsKey('MembersToExclude'))
    {
        if ($null -eq $MembersToExclude -or (($MembersToExclude.Count -eq 1) -and ($MembersToExclude[0].Length -eq 0)))
        {
            $MembersToExclude = @();
        }
        Write-Verbose -Message ($localizedString.CheckingMembers -f 'Excluded');
        $MembersToExclude = [System.String[]] @(Remove-DuplicateMembers -Members $MembersToExclude);
        foreach ($member in $MembersToExclude)
        {
            if ($member -in $ExistingMembers)
            {
                Write-Verbose -Message ($localizedString.MemberNotInDesiredState -f $member);
                return $false;
            }
        }
    } #end if $MembersToExclude

    Write-Verbose -Message $localizedString.MembershipInDesiredState;
    return $true;

} #end function Test-Membership

function ConvertTo-TimeSpan
{
    [CmdletBinding()]
    [OutputType([System.TimeSpan])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.UInt32]
        $TimeSpan,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Seconds', 'Minutes', 'Hours', 'Days')]
        [System.String]
        $TimeSpanType
    )

    $newTimeSpanParams = @{ };
    switch ($TimeSpanType)
    {
        'Seconds'
        {
            $newTimeSpanParams['Seconds'] = $TimeSpan
        }
        'Minutes'
        {
            $newTimeSpanParams['Minutes'] = $TimeSpan
        }
        'Hours'
        {
            $newTimeSpanParams['Hours'] = $TimeSpan
        }
        'Days'
        {
            $newTimeSpanParams['Days'] = $TimeSpan
        }
    }
    return (New-TimeSpan @newTimeSpanParams)
} #end function ConvertTo-TimeSpan

<#
    .SYNOPSIS
        Converts a System.TimeSpan into the number of seconds, mintutes, hours or days.

    .PARAMETER TimeSpan
        TimeSpan to convert into an integer

    .PARAMETER TimeSpanType
        Convert timespan into the total number of seconds, minutes, hours or days.

    .EXAMPLE
        $Get-ADDefaultDomainPasswordPolicy

        ConvertFrom-TimeSpan
#>
function ConvertFrom-TimeSpan
{
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.TimeSpan]
        $TimeSpan,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Seconds', 'Minutes', 'Hours', 'Days')]
        [System.String]
        $TimeSpanType
    )

    switch ($TimeSpanType)
    {
        'Seconds'
        {
            return $TimeSpan.TotalSeconds -as [System.UInt32]
        }
        'Minutes'
        {
            return $TimeSpan.TotalMinutes -as [System.UInt32]
        }
        'Hours'
        {
            return $TimeSpan.TotalHours -as [System.UInt32]
        }
        'Days'
        {
            return $TimeSpan.TotalDays -as [System.UInt32]
        }
    }
} #end function ConvertFrom-TimeSpan

<#
    .SYNOPSIS
        Returns common AD cmdlet connection parameter for splatting
    .PARAMETER CommonName
        When specified, a CommonName overrides theUsed by the xADUser cmdletReturns the Identity as the Name key. For example, the Get-ADUser, Set-ADUser and
        Remove-ADUser cmdlets take an Identity parameter, but the New-ADUser cmdlet uses the
        Name parameter.
    .PARAMETER UseNameParameter
        Returns the Identity as the Name key. For example, the Get-ADUser, Set-ADUser and
        Remove-ADUser cmdlets take an Identity parameter, but the New-ADUser cmdlet uses the
        Name parameter.
    .EXAMPLE
        $getADUserParams = Get-CommonADParameters @PSBoundParameters

        Returns connection parameters suitable for Get-ADUser using the splatted cmdlet
        parameters.
    .EXAMPLE
        $newADUserParams = Get-CommonADParameters @PSBoundParameters -UseNameParameter

        Returns connection parameters suitable for New-ADUser using the splatted cmdlet
        parameters.
#>
function Get-ADCommonParameters
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('UserName', 'GroupName', 'ComputerName', 'ServiceAccountName')]
        [System.String]
        $Identity,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $CommonName,

        [Parameter()]
        [ValidateNotNull()]
        [Alias('DomainAdministratorCredential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.CredentialAttribute()]
        $Credential,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('DomainController')]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $UseNameParameter,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $PreferCommonName,

        ## Catch all to enable splatted $PSBoundParameters
        [Parameter(ValueFromRemainingArguments)]
        $RemainingArguments
    )

    if ($UseNameParameter)
    {
        if ($PreferCommonName -and ($PSBoundParameters.ContainsKey('CommonName')))
        {
            $adConnectionParameters = @{ Name = $CommonName; }
        }
        else
        {
            $adConnectionParameters = @{ Name = $Identity; }
        }
    }
    else
    {
        if ($PreferCommonName -and ($PSBoundParameters.ContainsKey('CommonName')))
        {
            $adConnectionParameters = @{ Identity = $CommonName; }
        }
        else
        {
            $adConnectionParameters = @{ Identity = $Identity; }
        }
    }

    if ($Credential)
    {
        $adConnectionParameters['Credential'] = $Credential;
    }

    if ($Server)
    {
        $adConnectionParameters['Server'] = $Server;
    }

    return $adConnectionParameters;
} #end function Get-ADCommonParameters

function ThrowInvalidOperationError
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorMessage
    )

    $exception = New-Object -TypeName System.InvalidOperationException -ArgumentList $ErrorMessage;
    $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidOperation;
    $errorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $exception, $ErrorId, $errorCategory, $null;
    throw $errorRecord;
}

function ThrowInvalidArgumentError
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorMessage
    )

    $exception = New-Object -TypeName System.ArgumentException -ArgumentList $ErrorMessage;
    $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidArgument;
    $errorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $exception, $ErrorId, $errorCategory, $null;
    throw $errorRecord;

} #end function ThrowInvalidArgumentError

## Internal function to test site availability
function Test-ADReplicationSite
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String] $SiteName,

        [Parameter(Mandatory = $true)]
        [System.String] $DomainName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential
    )

    Write-Verbose -Message ($localizedString.CheckingSite -f $SiteName);

    $existingDC = "$((Get-ADDomainController -Discover -DomainName $DomainName -ForceDiscover).HostName)";

    try
    {
        $site = Get-ADReplicationSite -Identity $SiteName -Server $existingDC -Credential $Credential;
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
    {
        return $false;
    }

    return ($null -ne $site);
}

function ConvertTo-DeploymentForestMode
{
    [CmdletBinding()]
    [OutputType([Microsoft.DirectoryServices.Deployment.Types.ForestMode])]
    param
    (
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ById')]
        [UInt16]
        $ModeId,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByName')]
        [AllowNull()]
        [System.Nullable``1[Microsoft.ActiveDirectory.Management.ADForestMode]]
        $Mode,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ModuleName = 'xActiveDirectory'
    )

    $convertedMode = $null

    if ($PSCmdlet.ParameterSetName -eq 'ByName' -and $Mode)
    {
        $convertedMode = $Mode -as [Microsoft.DirectoryServices.Deployment.Types.ForestMode]
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById')
    {
        $convertedMode = $ModeId -as [Microsoft.DirectoryServices.Deployment.Types.ForestMode]
    }

    if ([enum]::GetValues([Microsoft.DirectoryServices.Deployment.Types.ForestMode]) -notcontains $convertedMode)
    {
        return $null
    }

    return $convertedMode
}

function ConvertTo-DeploymentDomainMode
{
    [CmdletBinding()]
    [OutputType([Microsoft.DirectoryServices.Deployment.Types.DomainMode])]
    param
    (
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ById')]
        [UInt16]
        $ModeId,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByName')]
        [AllowNull()]
        [System.Nullable``1[Microsoft.ActiveDirectory.Management.ADDomainMode]]
        $Mode,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ModuleName = 'xActiveDirectory'
    )

    $convertedMode = $null

    if ($PSCmdlet.ParameterSetName -eq 'ByName' -and $Mode)
    {
        $convertedMode = $Mode -as [Microsoft.DirectoryServices.Deployment.Types.DomainMode]
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById')
    {
        $convertedMode = $ModeId -as [Microsoft.DirectoryServices.Deployment.Types.DomainMode]
    }

    if ([enum]::GetValues([Microsoft.DirectoryServices.Deployment.Types.DomainMode]) -notcontains $convertedMode)
    {
        return $null
    }

    return $convertedMode
}

function Restore-ADCommonObject
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('UserName', 'GroupName', 'ComputerName', 'ServiceAccountName')]
        [System.String]
        $Identity,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Computer', 'OrganizationalUnit', 'User', 'Group')]
        [System.String]
        $ObjectClass,

        [Parameter()]
        [ValidateNotNull()]
        [Alias('DomainAdministratorCredential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.CredentialAttribute()]
        $Credential,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('DomainController')]
        [System.String]
        $Server
    )

    $restoreFilter = 'msDS-LastKnownRDN -eq "{0}" -and objectClass -eq "{1}" -and isDeleted -eq $true' -f $Identity, $ObjectClass
    Write-Verbose -Message ($localizedString.FindInRecycleBin -f $restoreFilter) -Verbose

    <#
        Using IsDeleted and IncludeDeletedObjects will mean that the cmdlet does not throw
        any more, and simply returns $null instead
    #>
    $commonParams = Get-ADCommonParameters @PSBoundParameters
    $getAdObjectParams = $commonParams.Clone()
    $getAdObjectParams.Remove('Identity')
    $getAdObjectParams['Filter'] = $restoreFilter
    $getAdObjectParams['IncludeDeletedObjects'] = $true
    $getAdObjectParams['Properties'] = @('whenChanged')

    # If more than one object is returned, we pick the one that was changed last.
    $restorableObject = Get-ADObject @getAdObjectParams |
        Sort-Object -Descending -Property 'whenChanged' |
        Select-Object -First 1

    $restoredObject = $null

    if ($restorableObject)
    {
        Write-Verbose -Message ($localizedString.FoundRestoreTargetInRecycleBin -f $Identity, $ObjectClass, $restorableObject.DistinguishedName) -Verbose

        try
        {
            $restoreParams = $commonParams.Clone()
            $restoreParams['PassThru'] = $true
            $restoreParams['ErrorAction'] = 'Stop'
            $restoreParams['Identity'] = $restorableObject.DistinguishedName
            $restoredObject = Restore-ADObject @restoreParams
            Write-Verbose -Message ($localizedString.RecycleBinRestoreSuccessful -f $Identity, $ObjectClass) -Verbose
        }
        catch [Microsoft.ActiveDirectory.Management.ADException]
        {
            # After Get-TargetResource is through, only one error can occur here: Object parent does not exist
            ThrowInvalidOperationError -ErrorId "$($Identity)_RecycleBinRestoreFailed" -ErrorMessage ($localizedString.RecycleBinRestoreFailed -f $Identity, $ObjectClass, $_.Exception.Message)
        }
    }

    return $restoredObject
}

<#
    .SYNOPSIS
        Author: Robert D. Biddle (https://github.com/RobBiddle)
        Created: December.20.2017

    .DESCRIPTION
        Takes an Active Directory DistinguishedName as input, returns the domain FQDN

    .EXAMPLE
        Get-ADDomainNameFromDistinguishedName -DistinguishedName 'CN=ExampleObject,OU=ExampleOU,DC=example,DC=com'
#>
function Get-ADDomainNameFromDistinguishedName
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.String]
        $DistinguishedName
    )

    if ($DistinguishedName -notlike '*DC=*')
    {
        return
    }

    $splitDistinguishedName = ($DistinguishedName -split 'DC=')
    $splitDistinguishedNameParts = $splitDistinguishedName[1..$splitDistinguishedName.Length]
    $domainFqdn = ""
    foreach ($part in $splitDistinguishedNameParts)
    {
        $domainFqdn += "DC=$part"
    }

    $domainName = $domainFqdn -replace 'DC=', '' -replace ',', '.'
    return $domainName

} #end function Get-ADDomainNameFromDistinguishedName

<#
    .SYNOPSIS
        Add group member from current or different domain

    .NOTES
        Author original code: Robert D. Biddle (https://github.com/RobBiddle)
        Author refactored code: Jan-Hendrik Peters (https://github.com/nyanhp)
#>
function Add-ADCommonGroupMember
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string[]]
        $Members,

        [Parameter()]
        [hashtable]
        $Parameters,

        [Parameter()]
        [switch]
        $MembersInMultipleDomains
    )

    Assert-Module -ModuleName ActiveDirectory

    if ($MembersInMultipleDomains.IsPresent)
    {
        foreach ($member in $Members)
        {
            $memberDomain = Get-ADDomainNameFromDistinguishedName -DistinguishedName $member

            if (-not $memberDomain)
            {
                ThrowInvalidArgumentError -ErrorId "$($member)_EmptyDomainError" -ErrorMessage ($localizedString.EmptyDomainError -f $member, $Parameters.GroupName)
            }

            Write-Verbose -Message ($localizedString.AddingGroupMember -f $member, $memberDomain, $Parameters.GroupName)
            $memberObjectClass = (Get-ADObject -Identity $member -Server $memberDomain -Properties ObjectClass).ObjectClass
            if ($memberObjectClass -eq 'computer')
            {
                $memberObject = Get-ADComputer -Identity $member -Server $memberDomain
            }
            elseif ($memberObjectClass -eq 'group')
            {
                $memberObject = Get-ADGroup -Identity $member -Server $memberDomain
            }
            elseif ($memberObjectClass -eq 'user')
            {
                $memberObject = Get-ADUser -Identity $member -Server $memberDomain
            }

            Add-ADGroupMember @Parameters -Members $memberObject
        }
    }
    else
    {
        Add-ADGroupMember @Parameters -Members $Members
    }
}

<#
    .SYNOPSIS
        Returns the domain controller object if the node is a domain controller,
        otherwise it return $null.

    .PARAMETER DomainName
        The name of the domain that should contain the domain controller.

    .PARAMETER ComputerName
        The name of the node to return the domain controller object for.
        Defaults to $env:COMPUTERNAME.

    .OUTPUTS
        If the domain controller is not found, an empty object ($null) is returned.

    .NOTES
        Throws an exception of Microsoft.ActiveDirectory.Management.ADServerDownException
        if the domain cannot be contacted.
#>
function Get-DomainControllerObject
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DomainName,

        [Parameter()]
        [System.String]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential
    )

    <#
        It is not possible to use `-ErrorAction 'SilentlyContinue` on the
        cmdlet Get-ADDomainController, it will throw an error regardless.
    #>
    try
    {
        $getADDomainControllerParameters = @{
            Filter = 'Name -eq "{0}"' -f $ComputerName
            Server = $DomainName
        }

        if ($PSBoundParameters.ContainsKey('Credential'))
        {
            $getADDomainControllerParameters['Credential'] = $Credential
        }

        $domainControllerObject = Get-ADDomainController @getADDomainControllerParameters

        if (-not $domainControllerObject -and (Test-IsDomainController) -eq $true)
        {
            $errorMessage = $script:localizedData.WasExpectingDomainController
            New-InvalidResultException -Message $errorMessage
        }
    }
    catch
    {
        $errorMessage = $localizedString.FailedEvaluatingDomainController
        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }

    return $domainControllerObject
}

<#
    .SYNOPSIS
        Returns $true if the node is a domain controller, otherwise it returns
        $false
#>
function Test-IsDomainController
{
    [CmdletBinding()]
    param
    (
    )

    $operatingSystemInformation = Get-CimInstance -ClassName 'Win32_OperatingSystem'

    return $operatingSystemInformation.ProductType -eq 2
}

<#
    .SYNOPSIS
        Converts a hashtable containing the parameter to property mappings to
        an array of properties that can be used to call cmdlets that supports the
        parameter Properties.

    .PARAMETER PropertyMap
        The property map, as an array of hashtables, to convert to a properties array.

    .EXAMPLE
        $computerObjectPropertyMap = @(
            @{
                ParameterName = 'ComputerName'
                PropertyName  = 'cn'
            },
            @{
                ParameterName = 'Location'
            }
        )

        $computerObjectProperties = Convert-PropertyMapToObjectProperties $computerObjectPropertyMap
        $getADComputerResult = Get-ADComputer -Identity 'APP01' -Properties $computerObjectProperties
#>
function Convert-PropertyMapToObjectProperties
{
    [CmdletBinding()]
    [OutputType([System.Array])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Array]
        $PropertyMap
    )

    $objectProperties = @()

    # Create an array of the AD property names to retrieve from the property map
    foreach ($property in $PropertyMap)
    {
        if ($property -isnot [System.Collections.Hashtable])
        {
            $errorMessage = $localizedString.PropertyMapArrayIsWrongType
            New-InvalidOperationException -Message $errorMessage
        }

        if ($property.ContainsKey('PropertyName'))
        {
            $objectProperties += @($property.PropertyName)
        }
        else
        {
            $objectProperties += $property.ParameterName
        }
    }

    return $objectProperties
}

<#
    .SYNOPSIS
        This function is used to compare current and desired values for any DSC
        resource, and return a hashtable with the result from the comparison.

    .PARAMETER CurrentValues
        The current values that should be compared to to desired values. Normally
        the values returned from Get-TargetResource.

    .PARAMETER DesiredValues
        The values set in the configuration and is provided in the call to the
        functions *-TargetResource, and that will be compared against current
        values. Normally set to $PSBoundParameters.

    .PARAMETER Properties
        An array of property names to filter out from the keys provided in
        DesiredValues. If left out, only those keys in the DesiredValues will
        be compared. This parameter can be used to remove certain keys from
        the comparison.
#>
function Compare-ResourcePropertyState
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $CurrentValues,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $DesiredValues,

        [Parameter()]
        [System.String[]]
        $Properties,

        [Parameter()]
        [System.String[]]
        $IgnoreProperties
    )

    if ($PSBoundParameters.ContainsKey('Properties'))
    {
        # Filter out the parameters (keys) not specified in Properties
        $desiredValuesToRemove = $DesiredValues.Keys | Where-Object -FilterScript {
            $_ -notin $Properties
        }

        $desiredValuesToRemove | ForEach-Object -Process {
            $DesiredValues.Remove($_)
        }
    }
    else
    {
        <#
            Remove any common parameters that might be part of DesiredValues,
            if it $PSBoundParameters was used to pass the desired values.
        #>
        $commonParametersToRemove = $DesiredValues.Keys | Where-Object -FilterScript {
            $_ -in [System.Management.Automation.PSCmdlet]::CommonParameters `
                -or $_ -in [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        }

        $commonParametersToRemove | ForEach-Object -Process {
            $DesiredValues.Remove($_)
        }
    }

    # Remove any properties that should be ignored.
    if ($PSBoundParameters.ContainsKey('IgnoreProperties'))
    {
        $IgnoreProperties | ForEach-Object -Process {
            if ($DesiredValues.ContainsKey($_))
            {
                $DesiredValues.Remove($_)
            }
        }
    }

    $compareTargetResourceStateReturnValue = @()

    foreach ($parameterName in $DesiredValues.Keys)
    {
        Write-Verbose -Message ($localizedString.EvaluatePropertyState -f $parameterName) -Verbose

        $parameterState = @{
            ParameterName = $parameterName
            Expected      = $DesiredValues.$parameterName
            Actual        = $CurrentValues.$parameterName
        }

        # Check if the parameter is in compliance.
        $isPropertyInDesiredState = Test-DscPropertyState -Values @{
            CurrentValue = $CurrentValues.$parameterName
            DesiredValue = $DesiredValues.$parameterName
        }

        if ($isPropertyInDesiredState)
        {
            Write-Verbose -Message ($localizedString.PropertyInDesiredState -f $parameterName) -Verbose

            $parameterState['InDesiredState'] = $true
        }
        else
        {
            Write-Verbose -Message ($localizedString.PropertyNotInDesiredState -f $parameterName) -Verbose

            $parameterState['InDesiredState'] = $false
        }

        $compareTargetResourceStateReturnValue += $parameterState
    }

    return $compareTargetResourceStateReturnValue
}

<#
    .SYNOPSIS
        This function is used to compare the current and the desired value of a
        property.

    .PARAMETER Values
        This is set to a hash table with the current value (the CurrentValue key)
        and desired value (the DesiredValue key).

    .EXAMPLE
        Test-DscPropertyState -Values @{
            CurrentValue = 'John'
            DesiredValue = 'Alice'
        }
    .EXAMPLE
        Test-DscPropertyState -Values @{
            CurrentValue = 1
            DesiredValue = 2
        }
#>
function Test-DscPropertyState
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Values
    )

    $returnValue = $true

    if ($Values.CurrentValue -ne $Values.DesiredValue -or $Values.DesiredValue.GetType().IsArray)
    {
        $desiredType = $Values.DesiredValue.GetType()

        if ($desiredType.IsArray -eq $true)
        {
            if ($Values.CurrentValue -and $Values.DesiredValue)
            {
                $compareObjectParameters = @{
                    ReferenceObject  = $Values.CurrentValue
                    DifferenceObject = $Values.DesiredValue
                }

                $arrayCompare = Compare-Object @compareObjectParameters

                if ($null -ne $arrayCompare)
                {
                    Write-Verbose -Message $localizedString.ArrayDoesNotMatch -Verbose

                    $arrayCompare | ForEach-Object -Process {
                        Write-Verbose -Message ($localizedString.ArrayValueThatDoesNotMatch -f $_.InputObject, $_.SideIndicator) -Verbose
                    }

                    $returnValue = $false
                }
            }
            else
            {
                $returnValue = $false
            }
        }
        else
        {
            $returnValue = $false

            $supportedTypes = @(
                'String'
                'Int32'
                'Int16'
                'UInt16'
                'Single'
                'Boolean'
            )

            if ($desiredType.Name -notin $supportedTypes)
            {
                Write-Warning -Message ($localizedString.UnableToCompareType `
                        -f $fieldName, $desiredType.Name)
            }
            else
            {
                Write-Verbose -Message (
                    $localizedString.PropertyValueOfTypeDoesNotMatch `
                        -f $desiredType.Name, $Values.CurrentValue, $Values.DesiredValue
                ) -Verbose
            }
        }
    }

    return $returnValue
}
