#Requires -Version 5.1

<#
.SYNOPSIS
    Haalt alle PIM en permanente rol gebruikers op voor meerdere tenants
    
.DESCRIPTION
    Dit script gebruikt Microsoft Graph API om alle gebruikers op te halen die:
    - Een PIM-rol hebben (permanent of eligible)
    - Permanente rollen hebben (zonder PIM)
    - Vergelijkt PIM vs permanent gebruik per tenant
    
.PARAMETER ConfigFile
    Pad naar het configuratie bestand (standaard: config.json)
    
.PARAMETER OutputPath  
    Pad waar de export bestanden worden opgeslagen (overschrijft config.json instelling)
    
.PARAMETER ReportOnly
    Genereer alleen HTML rapport uit bestaande exports zonder nieuwe data op te halen
    
.EXAMPLE
    .\Get-PIMUsers.ps1
    
.EXAMPLE
    .\Get-PIMUsers.ps1 -ConfigFile "custom-config.json" -OutputPath "C:\Exports"
    
.EXAMPLE
    .\Get-PIMUsers.ps1 -ReportOnly
    
.AUTEUR
    PowerShell Script voor PIM & Permanent Role Rapportage
    
.VERSIE
    1.0
#>

param(
    [string]$ConfigFile = "config.json",
    [string]$OutputPath = "",
    [switch]$ReportOnly
)

# Versie informatie
$ProjectVersion = "1.0"
$LastEditDate = "2025-08-16"

# Functie voor het controleren en installeren van PowerShell modules
function Install-RequiredModules {
    param(
        [string[]]$ModuleNames
    )
    
    Write-Host "Controleren van benodigde PowerShell modules..." -ForegroundColor Cyan
    
    foreach ($ModuleName in $ModuleNames) {
        Write-Host "Verwerken van module: $ModuleName" -ForegroundColor White
        
        $Module = Get-Module -ListAvailable -Name $ModuleName
        
        if (-not $Module) {
            Write-Host "Module '$ModuleName' niet gevonden. Bezig met installeren..." -ForegroundColor Yellow
            try {
                Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber
                Write-Host "Module '$ModuleName' succesvol geïnstalleerd." -ForegroundColor Green
            }
            catch {
                Write-Error "Fout bij installeren van module '$ModuleName': $($_.Exception.Message)"
                throw
            }
        }
        else {
            Write-Host "Module '$ModuleName' is al aanwezig." -ForegroundColor Green
        }
        
        # Importeer de module
        Write-Host "Importeren van module '$ModuleName'..." -ForegroundColor White
        try {
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Host "Module '$ModuleName' geïmporteerd." -ForegroundColor Green
        }
        catch {
            Write-Error "Fout bij importeren van module '$ModuleName': $($_.Exception.Message)"
            throw
        }
    }
    
    Write-Host "Module controle voltooid." -ForegroundColor Green
}

# Functie om configuratie te laden
function Get-ScriptConfig {
    param(
        [string]$ConfigFile,
        [string]$OutputPathOverride
    )
    
    # Standaard configuratie
    $defaultConfig = @{
        ExportSettings = @{
            OutputFolder = "exports"
            CreateDateSubfolders = $false
            ArchiveOldReports = $true
            MaxReportsToKeep = 10
        }
        ReportSettings = @{
            IncludeTimestamp = $true
            FileEncoding = "UTF8"
            DateFormat = "yyyyMMdd_HHmmss"
            IncludeServicePrincipals = $true
        }
    }
    
    # Probeer configuratie bestand te laden
    if (Test-Path $ConfigFile) {
        try {
            $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            Write-Host "✓ Configuratie geladen uit: $ConfigFile" -ForegroundColor Green
            
            # Override met geladen configuratie
            if ($configData.ExportSettings) {
                foreach ($key in $configData.ExportSettings.PSObject.Properties.Name) {
                    $defaultConfig.ExportSettings[$key] = $configData.ExportSettings.$key
                }
            }
            if ($configData.ReportSettings) {
                foreach ($key in $configData.ReportSettings.PSObject.Properties.Name) {
                    $defaultConfig.ReportSettings[$key] = $configData.ReportSettings.$key
                }
            }
        }
        catch {
            Write-Warning "Kon configuratie bestand niet laden: $($_.Exception.Message). Gebruik standaard instellingen."
        }
    }
    else {
        Write-Warning "Configuratie bestand niet gevonden: $ConfigFile. Gebruik standaard instellingen."
    }
    
    # Override output path als parameter is gegeven
    if ($OutputPathOverride -and $OutputPathOverride -ne "") {
        $defaultConfig.ExportSettings.OutputFolder = $OutputPathOverride
        Write-Host "✓ Output pad overschreven via parameter: $OutputPathOverride" -ForegroundColor Yellow
    }
    
    return $defaultConfig
}

# Functie om export folder te maken en te beheren
function Initialize-ExportFolder {
    param(
        [hashtable]$Config
    )
    
    $outputFolder = $Config.ExportSettings.OutputFolder
    
    # Maak absolute pad
    if (-not [System.IO.Path]::IsPathRooted($outputFolder)) {
        $outputFolder = Join-Path (Get-Location) $outputFolder
    }
    
    # Maak folder aan als deze niet bestaat
    if (-not (Test-Path $outputFolder)) {
        try {
            New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
            Write-Host "✓ Export folder aangemaakt: $outputFolder" -ForegroundColor Green
        }
        catch {
            Write-Error "Kon export folder niet aanmaken: $($_.Exception.Message)"
            return $null
        }
    }
    else {
        Write-Host "✓ Export folder bestaat: $outputFolder" -ForegroundColor Green
    }
    
    # Archiveer oude rapporten indien ingesteld
    if ($Config.ExportSettings.ArchiveOldReports -and $Config.ExportSettings.MaxReportsToKeep -gt 0) {
        try {
            $existingReports = Get-ChildItem -Path $outputFolder -Filter "*PIM*Users*.csv" | Sort-Object CreationTime -Descending
            $reportsToRemove = $existingReports | Select-Object -Skip $Config.ExportSettings.MaxReportsToKeep
            
            foreach ($report in $reportsToRemove) {
                Remove-Item $report.FullName -Force
                Write-Host "  - Oud rapport verwijderd: $($report.Name)" -ForegroundColor Gray
            }
            
            if ($reportsToRemove.Count -gt 0) {
                Write-Host "✓ $($reportsToRemove.Count) oude rapporten gearchiveerd" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Kon oude rapporten niet archiveren: $($_.Exception.Message)"
        }
    }
    
    return $outputFolder
}

# Functie om verbinding te maken met Microsoft Graph
function Connect-MicrosoftGraph {
    param(
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$TenantId
    )
    
    try {
        Write-Host "Verbinding maken met Microsoft Graph voor tenant: $TenantId" -ForegroundColor Yellow
        
        # Maak een credential object
        $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
        
        # Connect met Graph
        Connect-MgGraph -ClientSecretCredential $credential -TenantId $TenantId -NoWelcome
        
        Write-Host "✓ Succesvol verbonden met Microsoft Graph" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Fout bij verbinden met Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

# Functie om groepsleden op te halen
function Get-GroupMembers {
    param(
        [string]$GroupId,
        [string]$Customer,
        [string]$GroupName,
        [string]$RoleName,
        [string]$AssignmentType,
        [string]$AssignmentState,
        [DateTime]$StartDateTime,
        [DateTime]$EndDateTime
    )
    
    $groupMembers = @()
    
    try {
        Write-Host "    - Ophalen leden van groep: $GroupName (rol: $RoleName)"
        $members = Get-MgGroupMember -GroupId $GroupId -All -ErrorAction Stop
        
        foreach ($member in $members) {
            $memberInfo = Get-PrincipalInfo -PrincipalId $member.Id
            
            $memberResult = [PSCustomObject]@{
                Customer = $Customer
                UserType = $memberInfo.UserType
                DisplayName = $memberInfo.DisplayName
                UserPrincipalName = $memberInfo.UserPrincipalName
                Email = $memberInfo.Email
                AccountEnabled = $memberInfo.AccountEnabled
                CreatedDateTime = $memberInfo.CreatedDateTime
                Department = $memberInfo.Department
                JobTitle = $memberInfo.JobTitle
                CompanyName = $memberInfo.CompanyName
                PrincipalId = $member.Id
                RoleName = $RoleName
                AssignmentType = $AssignmentType
                AssignmentState = $AssignmentState
                StartDateTime = $StartDateTime
                EndDateTime = $EndDateTime
                ViaGroup = $GroupName
                IsGroupMember = $true
            }
            
            # Skip als het lid zelf weer een groep is (om oneindige loops te voorkomen)
            if ($memberResult.UserType -ne "Group") {
                $groupMembers += $memberResult
            }
        }
        
        Write-Host "      └─ Gevonden $($groupMembers.Count) leden in groep $GroupName voor rol $RoleName"
    }
    catch {
        Write-Warning "Kon groepsleden niet ophalen voor groep: $GroupId ($GroupName). Fout: $($_.Exception.Message)"
    }
    
    return $groupMembers
}

# Helper functie om gebruiker informatie op te halen
function Get-PrincipalInfo {
    param(
        [string]$PrincipalId
    )
    
    $result = @{
        UserType = "Unknown"
        DisplayName = "Unknown"
        UserPrincipalName = "Unknown"
        Email = "Unknown"
        AccountEnabled = $null
        CreatedDateTime = $null
        Department = "Unknown"
        JobTitle = "Unknown"
        CompanyName = "Unknown"
    }
    
    if (-not $PrincipalId) {
        return $result
    }
    
    try {
        # Probeer als gebruiker
        try {
            $userDetails = Get-MgUser -UserId $PrincipalId -ErrorAction Stop
            $result.UserType = "User"
            $result.DisplayName = $userDetails.DisplayName
            $result.UserPrincipalName = $userDetails.UserPrincipalName
            $result.Email = $userDetails.Mail
            $result.AccountEnabled = $userDetails.AccountEnabled
            $result.CreatedDateTime = $userDetails.CreatedDateTime
            $result.Department = $userDetails.Department
            $result.JobTitle = $userDetails.JobTitle
            $result.CompanyName = $userDetails.CompanyName
            return $result
        }
        catch {
            # Probeer als service principal
            try {
                $spDetails = Get-MgServicePrincipal -ServicePrincipalId $PrincipalId -ErrorAction Stop
                $result.UserType = "ServicePrincipal"
                $result.DisplayName = $spDetails.DisplayName
                $result.UserPrincipalName = "SERVICE PRINCIPAL"
                $result.Email = "N/A"
                $result.AccountEnabled = $spDetails.AccountEnabled
                $result.CreatedDateTime = $spDetails.CreatedDateTime
                return $result
            }
            catch {
                # Probeer als groep
                try {
                    $groupDetails = Get-MgGroup -GroupId $PrincipalId -ErrorAction Stop
                    $result.UserType = "Group"
                    $result.DisplayName = $groupDetails.DisplayName
                    $result.UserPrincipalName = "GROUP"
                    $result.Email = $groupDetails.Mail
                    $result.AccountEnabled = $true
                    $result.CreatedDateTime = $groupDetails.CreatedDateTime
                    return $result
                }
                catch {
                    Write-Warning "Kon principal niet ophalen voor ID: $PrincipalId"
                    return $result
                }
            }
        }
    }
    catch {
        Write-Warning "Fout bij ophalen principal info voor $PrincipalId : $($_.Exception.Message)"
        return $result
    }
}

# Functie om PIM rol assignments op te halen
function Get-PIMRoleAssignments {
    param(
        [string]$TenantId,
        [string]$CustomerName
    )
    
    $allPIMAssignments = @()
    
    try {
        Write-Host "Ophalen van PIM rol-toewijzingen voor $CustomerName..." -ForegroundColor Yellow
        
        # Haal alle eligible role assignments op (PIM candidates)
        Write-Host "  - Ophalen van eligible assignments..." -ForegroundColor Cyan
        try {
            $eligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -ErrorAction SilentlyContinue
            
            foreach ($assignment in $eligibleAssignments) {
                try {
                    # Haal rol informatie op
                    $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $assignment.RoleDefinitionId -ErrorAction SilentlyContinue
                    if (-not $roleDefinition) { continue }
                    
                    # Haal gebruiker informatie op
                    $principalInfo = Get-PrincipalInfo -PrincipalId $assignment.PrincipalId
                    
                    $pimInfo = [PSCustomObject]@{
                        Customer = $CustomerName
                        TenantId = $TenantId
                        UserPrincipalName = $principalInfo.UserPrincipalName
                        DisplayName = $principalInfo.DisplayName
                        PrincipalId = $assignment.PrincipalId
                        EmailAddress = $principalInfo.Email
                        UserType = $principalInfo.UserType
                        RoleName = $roleDefinition.DisplayName
                        RoleId = $roleDefinition.Id
                        RoleTemplateId = $roleDefinition.TemplateId
                        AssignmentType = "Eligible"
                        Status = $assignment.Status
                        CreatedDateTime = $assignment.CreatedDateTime
                        StartDateTime = $assignment.ScheduleInfo.StartDateTime
                        EndDateTime = $assignment.ScheduleInfo.Expiration.EndDateTime
                        DirectoryScope = $assignment.DirectoryScopeId
                        AssignmentId = $assignment.Id
                        AccountEnabled = $principalInfo.AccountEnabled
                        Department = $principalInfo.Department
                        JobTitle = $principalInfo.JobTitle
                        CompanyName = $principalInfo.CompanyName
                        IsPIMManaged = $true
                        ViaGroup = "N/A"
                        IsGroupMember = $false
                    }
                    $allPIMAssignments += $pimInfo
                    
                    # Als dit een groep is, haal dan ook de leden op
                    if ($principalInfo.UserType -eq "Group") {
                        $startDate = if ($assignment.ScheduleInfo.StartDateTime) { $assignment.ScheduleInfo.StartDateTime } else { [DateTime]::MinValue }
                        $endDate = if ($assignment.ScheduleInfo.Expiration.EndDateTime) { $assignment.ScheduleInfo.Expiration.EndDateTime } else { [DateTime]::MaxValue }
                        
                        $groupMembers = Get-GroupMembers -GroupId $assignment.PrincipalId -Customer $CustomerName -GroupName $principalInfo.DisplayName -RoleName $roleDefinition.DisplayName -AssignmentType "Eligible" -AssignmentState $assignment.Status -StartDateTime $startDate -EndDateTime $endDate
                        foreach ($member in $groupMembers) {
                            $memberPimInfo = [PSCustomObject]@{
                                Customer = $member.Customer
                                TenantId = $TenantId
                                UserPrincipalName = $member.UserPrincipalName
                                DisplayName = $member.DisplayName
                                PrincipalId = $member.PrincipalId
                                EmailAddress = $member.Email
                                UserType = $member.UserType
                                RoleName = $member.RoleName
                                RoleId = $roleDefinition.Id
                                RoleTemplateId = $roleDefinition.TemplateId
                                AssignmentType = $member.AssignmentType
                                Status = $assignment.Status
                                CreatedDateTime = $assignment.CreatedDateTime
                                StartDateTime = $member.StartDateTime
                                EndDateTime = $member.EndDateTime
                                DirectoryScope = $assignment.DirectoryScopeId
                                AssignmentId = $assignment.Id + "_member_" + $member.PrincipalId
                                AccountEnabled = $member.AccountEnabled
                                Department = $member.Department
                                JobTitle = $member.JobTitle
                                CompanyName = $member.CompanyName
                                IsPIMManaged = $true
                                ViaGroup = $member.ViaGroup
                                IsGroupMember = $member.IsGroupMember
                            }
                            $allPIMAssignments += $memberPimInfo
                        }
                    }
                }
                catch {
                    Write-Warning "Fout bij verwerken van eligible assignment: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Warning "Kon eligible assignments niet ophalen: $($_.Exception.Message)"
        }
        
        # Haal alle active role assignments op (permanent assignments via PIM)
        Write-Host "  - Ophalen van active assignments..." -ForegroundColor Cyan
        try {
            $activeAssignments = Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All -ErrorAction SilentlyContinue
            
            foreach ($assignment in $activeAssignments) {
                try {
                    # Haal rol informatie op
                    $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $assignment.RoleDefinitionId -ErrorAction SilentlyContinue
                    if (-not $roleDefinition) { continue }
                    
                    # Haal gebruiker informatie op
                    $principalInfo = Get-PrincipalInfo -PrincipalId $assignment.PrincipalId
                    
                    # Bepaal of dit een permanente of tijdelijke (PIM) active assignment is
                    $assignmentType = "Active"
                    $isPermanent = $false
                    
                    # Als er geen eindtijd is of eindtijd is ver in de toekomst (> 1 jaar), dan is het permanent
                    $endDateTime = $assignment.ScheduleInfo.Expiration.EndDateTime
                    if (-not $endDateTime -or 
                        [string]::IsNullOrEmpty($endDateTime) -or
                        $endDateTime -gt (Get-Date).AddYears(1)) {
                        $assignmentType = "Permanent"
                        $isPermanent = $true
                    }
                    
                    $pimInfo = [PSCustomObject]@{
                        Customer = $CustomerName
                        TenantId = $TenantId
                        UserPrincipalName = $principalInfo.UserPrincipalName
                        DisplayName = $principalInfo.DisplayName
                        PrincipalId = $assignment.PrincipalId
                        EmailAddress = $principalInfo.Email
                        UserType = $principalInfo.UserType
                        RoleName = $roleDefinition.DisplayName
                        RoleId = $roleDefinition.Id
                        RoleTemplateId = $roleDefinition.TemplateId
                        AssignmentType = $assignmentType
                        Status = $assignment.Status
                        CreatedDateTime = $assignment.CreatedDateTime
                        StartDateTime = $assignment.ScheduleInfo.StartDateTime
                        EndDateTime = if ($isPermanent) { "Never" } else { $assignment.ScheduleInfo.Expiration.EndDateTime }
                        DirectoryScope = $assignment.DirectoryScopeId
                        AssignmentId = $assignment.Id
                        AccountEnabled = $principalInfo.AccountEnabled
                        Department = $principalInfo.Department
                        JobTitle = $principalInfo.JobTitle
                        CompanyName = $principalInfo.CompanyName
                        IsPIMManaged = if ($isPermanent) { $false } else { $true }
                        ViaGroup = "N/A"
                        IsGroupMember = $false
                    }
                    $allPIMAssignments += $pimInfo
                    
                    # Als dit een groep is, haal dan ook de leden op
                    if ($principalInfo.UserType -eq "Group") {
                        $startDate = if ($assignment.ScheduleInfo.StartDateTime) { $assignment.ScheduleInfo.StartDateTime } else { [DateTime]::MinValue }
                        $endDate = if ($isPermanent) { [DateTime]::MaxValue } else { 
                            if ($assignment.ScheduleInfo.Expiration.EndDateTime) { $assignment.ScheduleInfo.Expiration.EndDateTime } else { [DateTime]::MaxValue }
                        }
                        
                        $groupMembers = Get-GroupMembers -GroupId $assignment.PrincipalId -Customer $CustomerName -GroupName $principalInfo.DisplayName -RoleName $roleDefinition.DisplayName -AssignmentType $assignmentType -AssignmentState $assignment.Status -StartDateTime $startDate -EndDateTime $endDate
                        foreach ($member in $groupMembers) {
                            $memberPimInfo = [PSCustomObject]@{
                                Customer = $member.Customer
                                TenantId = $TenantId
                                UserPrincipalName = $member.UserPrincipalName
                                DisplayName = $member.DisplayName
                                PrincipalId = $member.PrincipalId
                                EmailAddress = $member.Email
                                UserType = $member.UserType
                                RoleName = $member.RoleName
                                RoleId = $roleDefinition.Id
                                RoleTemplateId = $roleDefinition.TemplateId
                                AssignmentType = $member.AssignmentType
                                Status = $assignment.Status
                                CreatedDateTime = $assignment.CreatedDateTime
                                StartDateTime = $member.StartDateTime
                                EndDateTime = $member.EndDateTime
                                DirectoryScope = $assignment.DirectoryScopeId
                                AssignmentId = $assignment.Id + "_member_" + $member.PrincipalId
                                AccountEnabled = $member.AccountEnabled
                                Department = $member.Department
                                JobTitle = $member.JobTitle
                                CompanyName = $member.CompanyName
                                IsPIMManaged = if ($member.AssignmentType -eq "Permanent") { $false } else { $true }
                                ViaGroup = $member.ViaGroup
                                IsGroupMember = $member.IsGroupMember
                            }
                            $allPIMAssignments += $memberPimInfo
                        }
                    }
                }
                catch {
                    Write-Warning "Fout bij verwerken van active assignment: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Warning "Kon active assignments niet ophalen: $($_.Exception.Message)"
        }
        
        Write-Host "✓ Gevonden $($allPIMAssignments.Count) PIM rol-toewijzingen voor $CustomerName" -ForegroundColor Green
        return $allPIMAssignments
    }
    catch {
        Write-Error "Fout bij ophalen PIM rol-toewijzingen voor $CustomerName : $($_.Exception.Message)"
        return @()
    }
}

# Functie om permanente (non-PIM) rol assignments op te halen
# Functie om permanente (non-PIM) rol assignments op te halen
function Get-PermanentRoleAssignments {
    param(
        [string]$TenantId,
        [string]$CustomerName
    )
    
    $allPermanentAssignments = @()
    
    try {
        Write-Host "Ophalen van klassieke (non-PIM) rol-toewijzingen voor $CustomerName..." -ForegroundColor Yellow
        Write-Host "  (Permanente rollen zonder eindtijd worden al gedetecteerd in PIM Active assignments)" -ForegroundColor Gray
        
        # Method 1: Haal klassieke directory role assignments op (alleen als ze NIET in PIM zitten)
        Write-Host "  - Ophalen van klassieke directory role assignments..." -ForegroundColor Cyan
        try {
            $directoryRoleAssignments = Get-MgRoleManagementDirectoryRoleAssignment -All -ErrorAction SilentlyContinue
            Write-Host "    - Gevonden $($directoryRoleAssignments.Count) directory role assignments" -ForegroundColor DarkCyan
            
            foreach ($assignment in $directoryRoleAssignments) {
                try {
                    # Haal rol informatie op
                    $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $assignment.RoleDefinitionId -ErrorAction SilentlyContinue
                    if (-not $roleDefinition) { continue }
                    
                    # Check of dit assignment AL via PIM loopt (dus NIET klassiek permanent)
                    $isPIMManaged = $false
                    try {
                        # Kijk of er PIM eligible schedules zijn
                        $pimEligible = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -Filter "principalId eq '$($assignment.PrincipalId)' and roleDefinitionId eq '$($assignment.RoleDefinitionId)'" -ErrorAction SilentlyContinue
                        # Kijk of er PIM assignment schedules zijn (ook permanente)
                        $pimAssignment = Get-MgRoleManagementDirectoryRoleAssignmentSchedule -Filter "principalId eq '$($assignment.PrincipalId)' and roleDefinitionId eq '$($assignment.RoleDefinitionId)'" -ErrorAction SilentlyContinue
                        
                        if (($pimEligible | Measure-Object).Count -gt 0 -or ($pimAssignment | Measure-Object).Count -gt 0) {
                            $isPIMManaged = $true
                        }
                    }
                    catch {
                        $isPIMManaged = $false
                    }
                    
                    # Alleen verwerken als het NIET PIM-managed is (dus ouderwetse klassieke assignment)
                    if (-not $isPIMManaged) {
                        Write-Host "      - Klassieke permanente rol gevonden: $($roleDefinition.DisplayName) voor principal $($assignment.PrincipalId)" -ForegroundColor Green
                        
                        # Haal gebruiker/principal informatie op
                        $principalInfo = Get-PrincipalInfo -PrincipalId $assignment.PrincipalId
                        
                        $permanentInfo = [PSCustomObject]@{
                            Customer = $CustomerName
                            TenantId = $TenantId
                            UserPrincipalName = $principalInfo.UserPrincipalName
                            DisplayName = $principalInfo.DisplayName
                            PrincipalId = $assignment.PrincipalId
                            EmailAddress = $principalInfo.Email
                            UserType = $principalInfo.UserType
                            RoleName = $roleDefinition.DisplayName
                            RoleId = $roleDefinition.Id
                            RoleTemplateId = $roleDefinition.TemplateId
                            AssignmentType = "Permanent"
                            Status = "Active"
                            CreatedDateTime = $principalInfo.CreatedDateTime
                            StartDateTime = "N/A"
                            EndDateTime = "Never"
                            DirectoryScope = $assignment.DirectoryScopeId
                            AssignmentId = $assignment.Id
                            AccountEnabled = $principalInfo.AccountEnabled
                            Department = $principalInfo.Department
                            JobTitle = $principalInfo.JobTitle
                            CompanyName = $principalInfo.CompanyName
                            IsPIMManaged = $false
                            ViaGroup = "N/A"
                            IsGroupMember = $false
                        }
                        $allPermanentAssignments += $permanentInfo
                        
                        # Als dit een groep is, haal dan ook de leden op
                        if ($principalInfo.UserType -eq "Group") {
                            $groupMembers = Get-GroupMembers -GroupId $assignment.PrincipalId -Customer $CustomerName -GroupName $principalInfo.DisplayName -RoleName $roleDefinition.DisplayName -AssignmentType "Permanent" -AssignmentState "Active" -StartDateTime ([DateTime]::MinValue) -EndDateTime ([DateTime]::MaxValue)
                            foreach ($groupMember in $groupMembers) {
                                $memberPermanentInfo = [PSCustomObject]@{
                                    Customer = $groupMember.Customer
                                    TenantId = $TenantId
                                    UserPrincipalName = $groupMember.UserPrincipalName
                                    DisplayName = $groupMember.DisplayName
                                    PrincipalId = $groupMember.PrincipalId
                                    EmailAddress = $groupMember.Email
                                    UserType = $groupMember.UserType
                                    RoleName = $groupMember.RoleName
                                    RoleId = $roleDefinition.Id
                                    RoleTemplateId = $roleDefinition.TemplateId
                                    AssignmentType = $groupMember.AssignmentType
                                    Status = "Active"
                                    CreatedDateTime = $groupMember.CreatedDateTime
                                    StartDateTime = "N/A"
                                    EndDateTime = "Never"
                                    DirectoryScope = $assignment.DirectoryScopeId
                                    AssignmentId = $assignment.Id + "_member_" + $groupMember.PrincipalId
                                    AccountEnabled = $groupMember.AccountEnabled
                                    Department = $groupMember.Department
                                    JobTitle = $groupMember.JobTitle
                                    CompanyName = $groupMember.CompanyName
                                    IsPIMManaged = $false
                                    ViaGroup = $groupMember.ViaGroup
                                    IsGroupMember = $groupMember.IsGroupMember
                                }
                                $allPermanentAssignments += $memberPermanentInfo
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Fout bij verwerken van klassiek assignment: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Warning "Kon klassieke role assignments niet ophalen: $($_.Exception.Message)"
        }
        
        Write-Host "✓ Gevonden $($allPermanentAssignments.Count) permanente rol-toewijzingen voor $CustomerName" -ForegroundColor Green
        return $allPermanentAssignments
    }
    catch {
        Write-Error "Fout bij ophalen permanente rol-toewijzingen voor $CustomerName : $($_.Exception.Message)"
        return @()
    }
}

# Functie om wijzigingen te detecteren tussen exports
function Compare-PIMExports {
    param(
        [array]$CurrentResults,
        [string]$ExportPath,
        [string]$DatePrefix
    )
    
    $changes = @()
    
    try {
        Write-Host "Detecteren van wijzigingen ten opzichte van vorige export..." -ForegroundColor Yellow
        
        # Zoek naar vorige export bestanden (oudere datums dan huidige)
        $allFiles = Get-ChildItem -Path $ExportPath -Filter "*_All_Customers_Full_Report.csv" | 
                   Where-Object { $_.Name -notlike "$DatePrefix*" }
        
        if ($allFiles.Count -eq 0) {
            Write-Host "  - Geen vorige export gevonden. Dit is waarschijnlijk de eerste run." -ForegroundColor Gray
            return @()
        }
        
        # Sorteer op datum in bestandsnaam (nieuwste eerst)
        $previousFiles = $allFiles | Sort-Object { 
            # Extract datum uit bestandsnaam (YYYYMMDD)
            if ($_.Name -match '^(\d{8})_') { 
                [datetime]::ParseExact($matches[1], 'yyyyMMdd', $null) 
            } else { 
                $_.CreationTime 
            }
        } -Descending | Select-Object -First 1
        
        $previousFile = $previousFiles.FullName
        Write-Host "  - Vorige export gevonden: $($previousFiles.Name)" -ForegroundColor Cyan
        
        # Lees vorige export
        try {
            $previousResults = Import-Csv -Path $previousFile -ErrorAction Stop
            Write-Host "  - Vorige export geladen: $($previousResults.Count) records" -ForegroundColor Green
        }
        catch {
            Write-Warning "Kon vorige export niet laden: $($_.Exception.Message)"
            return @()
        }
        
        # Maak unieke identifiers voor vergelijking
        Write-Host "  - Analyseren van wijzigingen..." -ForegroundColor Cyan
        
        # Huidige data voorbereiden
        $currentLookup = @{}
        foreach ($record in $CurrentResults) {
            $key = "$($record.Customer)_$($record.PrincipalId)_$($record.RoleName)"
            $currentLookup[$key] = $record
        }
        
        # Vorige data voorbereiden  
        $previousLookup = @{}
        foreach ($record in $previousResults) {
            $key = "$($record.Customer)_$($record.PrincipalId)_$($record.RoleName)"
            $previousLookup[$key] = $record
        }
        
        # Detecteer nieuwe assignments
        foreach ($key in $currentLookup.Keys) {
            if (-not $previousLookup.ContainsKey($key)) {
                $record = $currentLookup[$key]
                $change = [PSCustomObject]@{
                    ChangeType = "NEW"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Customer = $record.Customer
                    DisplayName = $record.DisplayName
                    UserPrincipalName = $record.UserPrincipalName
                    RoleName = $record.RoleName
                    AssignmentType = $record.AssignmentType
                    UserType = $record.UserType
                    ViaGroup = $record.ViaGroup
                    PreviousValue = "N/A"
                    CurrentValue = "$($record.AssignmentType)"
                    Description = "Nieuwe rol toewijzing gedetecteerd"
                    PrincipalId = $record.PrincipalId
                }
                $changes += $change
            }
        }
        
        # Detecteer verwijderde assignments
        foreach ($key in $previousLookup.Keys) {
            if (-not $currentLookup.ContainsKey($key)) {
                $record = $previousLookup[$key]
                $change = [PSCustomObject]@{
                    ChangeType = "REMOVED"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Customer = $record.Customer
                    DisplayName = $record.DisplayName
                    UserPrincipalName = $record.UserPrincipalName
                    RoleName = $record.RoleName
                    AssignmentType = $record.AssignmentType
                    UserType = $record.UserType
                    ViaGroup = $record.ViaGroup
                    PreviousValue = "$($record.AssignmentType)"
                    CurrentValue = "N/A"
                    Description = "Rol toewijzing verwijderd"
                    PrincipalId = $record.PrincipalId
                }
                $changes += $change
            }
        }
        
        # Detecteer gewijzigde assignment types (bijv. Eligible -> Active)
        foreach ($key in $currentLookup.Keys) {
            if ($previousLookup.ContainsKey($key)) {
                $current = $currentLookup[$key]
                $previous = $previousLookup[$key]
                
                if ($current.AssignmentType -ne $previous.AssignmentType) {
                    $change = [PSCustomObject]@{
                        ChangeType = "MODIFIED"
                        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        Customer = $current.Customer
                        DisplayName = $current.DisplayName
                        UserPrincipalName = $current.UserPrincipalName
                        RoleName = $current.RoleName
                        AssignmentType = $current.AssignmentType
                        UserType = $current.UserType
                        ViaGroup = $current.ViaGroup
                        PreviousValue = $previous.AssignmentType
                        CurrentValue = $current.AssignmentType
                        Description = "Assignment type gewijzigd van $($previous.AssignmentType) naar $($current.AssignmentType)"
                        PrincipalId = $current.PrincipalId
                    }
                    $changes += $change
                }
                
                # Check voor wijzigingen in groepstoewijzing
                if ($current.ViaGroup -ne $previous.ViaGroup) {
                    $change = [PSCustomObject]@{
                        ChangeType = "MODIFIED"
                        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        Customer = $current.Customer
                        DisplayName = $current.DisplayName
                        UserPrincipalName = $current.UserPrincipalName
                        RoleName = $current.RoleName
                        AssignmentType = $current.AssignmentType
                        UserType = $current.UserType
                        ViaGroup = $current.ViaGroup
                        PreviousValue = $previous.ViaGroup
                        CurrentValue = $current.ViaGroup
                        Description = "Groepstoewijzing gewijzigd van '$($previous.ViaGroup)' naar '$($current.ViaGroup)'"
                        PrincipalId = $current.PrincipalId
                    }
                    $changes += $change
                }
            }
        }
        
        # Rapporteer resultaten
        $newCount = ($changes | Where-Object { $_.ChangeType -eq "NEW" }).Count
        $removedCount = ($changes | Where-Object { $_.ChangeType -eq "REMOVED" }).Count
        $modifiedCount = ($changes | Where-Object { $_.ChangeType -eq "MODIFIED" }).Count
        
        Write-Host "✓ Wijzigingsanalyse voltooid:" -ForegroundColor Green
        Write-Host "  - Nieuwe toewijzingen: $newCount" -ForegroundColor Green
        Write-Host "  - Verwijderde toewijzingen: $removedCount" -ForegroundColor Red
        Write-Host "  - Gewijzigde toewijzingen: $modifiedCount" -ForegroundColor Yellow
        
        # Exporteer wijzigingen naar CSV
        if ($changes.Count -gt 0) {
            $changesPath = Join-Path $ExportPath "${DatePrefix}_Changes_Report.csv"
            $changes | Export-Csv -Path $changesPath -NoTypeInformation -Encoding UTF8
            Write-Host "✓ Wijzigingen rapport opgeslagen: $changesPath" -ForegroundColor Green
        }
        
        return $changes
    }
    catch {
        Write-Error "Fout bij wijzigingsdetectie: $($_.Exception.Message)"
        return @()
    }
}

# Functie om HTML dashboard te genereren
function New-HTMLDashboard {
    param(
        [array]$AllResults,
        [string]$ExportPath,
        [string]$DatePrefix,
        [hashtable]$Config,
        [array]$Changes = @()
    )
    
    try {
        Write-Host "  - Voorbereiden HTML data..." -ForegroundColor Cyan
        
        # Groepeer data per klant
        $customerGroups = $AllResults | Group-Object Customer
        
        # Wijzigingen statistieken (altijd tonen, ook bij 0)
        $newChanges = ($Changes | Where-Object { $_.ChangeType -eq "NEW" }).Count
        $removedChanges = ($Changes | Where-Object { $_.ChangeType -eq "REMOVED" }).Count
        $modifiedChanges = ($Changes | Where-Object { $_.ChangeType -eq "MODIFIED" }).Count
        
        $changesStats = @"
        <div class="stat-card changes-new">
            <h4>Nieuwe Toewijzingen</h4>
            <div class="stat-number">$newChanges</div>
        </div>
        <div class="stat-card changes-removed">
            <h4>Verwijderde Toewijzingen</h4>
            <div class="stat-number">$removedChanges</div>
        </div>
        <div class="stat-card changes-modified">
            <h4>Gewijzigde Toewijzingen</h4>
            <div class="stat-number">$modifiedChanges</div>
        </div>
"@
        
        # Wijzigingen tab (altijd tonen)
        $changesTab = '<button class="tablinks" onclick="showChanges(event)"><i class="fa-solid fa-exchange-alt"></i> Wijzigingen</button>'
            
            # Bouw wijzigingen tabel
            $changesTableRows = ""
            foreach ($change in $Changes) {
                $changeTypeColor = switch ($change.ChangeType) {
                    "NEW" { "color: #28a745; font-weight: bold;" }
                    "REMOVED" { "color: #dc3545; font-weight: bold;" }
                    "MODIFIED" { "color: #ffc107; font-weight: bold;" }
                    default { "" }
                }
                
                $changeIcon = switch ($change.ChangeType) {
                    "NEW" { "fa-plus-circle" }
                    "REMOVED" { "fa-minus-circle" }
                    "MODIFIED" { "fa-edit" }
                    default { "fa-question-circle" }
                }
                
                $changesTableRows += @"
                <tr>
                    <td><i class="fa-solid $changeIcon" style="$changeTypeColor"></i> <span style="$changeTypeColor">$($change.ChangeType)</span></td>
                    <td>$($change.Timestamp)</td>
                    <td>$($change.Customer)</td>
                    <td>$($change.DisplayName)</td>
                    <td>$($change.UserPrincipalName)</td>
                    <td>$($change.RoleName)</td>
                    <td>$($change.PreviousValue)</td>
                    <td>$($change.CurrentValue)</td>
                    <td>$($change.Description)</td>
                </tr>
"@
            }
            
        # Wijzigingen content (altijd tonen)
        $changesTableRows = ""
        $noChangesMessage = ""
        
        if ($Changes.Count -gt 0) {
            # Bouw wijzigingen tabel
            foreach ($change in $Changes) {
                $changeTypeColor = switch ($change.ChangeType) {
                    "NEW" { "color: #28a745; font-weight: bold;" }
                    "REMOVED" { "color: #dc3545; font-weight: bold;" }
                    "MODIFIED" { "color: #ffc107; font-weight: bold;" }
                    default { "" }
                }
                
                $changeIcon = switch ($change.ChangeType) {
                    "NEW" { "fa-plus-circle" }
                    "REMOVED" { "fa-minus-circle" }
                    "MODIFIED" { "fa-edit" }
                    default { "fa-question-circle" }
                }
                
                $changesTableRows += @"
                <tr>
                    <td><i class="fa-solid $changeIcon" style="$changeTypeColor"></i> <span style="$changeTypeColor">$($change.ChangeType)</span></td>
                    <td>$($change.Timestamp)</td>
                    <td>$($change.Customer)</td>
                    <td>$($change.DisplayName)</td>
                    <td>$($change.UserPrincipalName)</td>
                    <td>$($change.RoleName)</td>
                    <td>$($change.PreviousValue)</td>
                    <td>$($change.CurrentValue)</td>
                    <td>$($change.Description)</td>
                </tr>
"@
            }
        } else {
            $noChangesMessage = @"
        <div style="text-align: center; padding: 40px; color: #6c757d; background: #f8f9fa; border-radius: 8px; margin: 20px 0;">
            <i class="fa-solid fa-check-circle" style="font-size: 48px; color: #28a745; margin-bottom: 15px;"></i>
            <h4 style="margin: 0 0 10px 0; color: #495057;">Geen wijzigingen gedetecteerd</h4>
            <p style="margin: 0; font-size: 16px;">Alle rol-toewijzingen zijn hetzelfde gebleven sinds de vorige export.</p>
        </div>
"@
        }
        
        $changesContent = @"
    <div id="Changes" class="tabcontent">
        <h3><i class="fa-solid fa-exchange-alt"></i> Wijzigingen sinds vorige export</h3>
        
        <div class="stats-grid">
            <div class="stat-card changes-new">
                <h4>Nieuwe Toewijzingen</h4>
                <div class="stat-number">$(($Changes | Where-Object { $_.ChangeType -eq "NEW" }).Count)</div>
            </div>
            <div class="stat-card changes-removed">
                <h4>Verwijderde Toewijzingen</h4>
                <div class="stat-number">$(($Changes | Where-Object { $_.ChangeType -eq "REMOVED" }).Count)</div>
            </div>
            <div class="stat-card changes-modified">
                <h4>Gewijzigde Toewijzingen</h4>
                <div class="stat-number">$(($Changes | Where-Object { $_.ChangeType -eq "MODIFIED" }).Count)</div>
            </div>
        </div>
        
        $noChangesMessage
        
        <h4>Alle Wijzigingen</h4>
        <table id="changesTable" class="display" style="width:100%">
            <thead>
                <tr>
                    <th>Type</th>
                    <th>Tijdstip</th>
                    <th>Klant</th>
                    <th>Naam</th>
                    <th>UPN</th>
                    <th>Rol</th>
                    <th>Vorige Waarde</th>
                    <th>Huidige Waarde</th>
                    <th>Beschrijving</th>
                </tr>
            </thead>
            <tbody>
                $changesTableRows
            </tbody>
        </table>
    </div>

"@

        # Bouw customer tabs
        $customerTabs = ""
        $customerTables = ""
        
        foreach ($customerGroup in $customerGroups) {
            $customerName = $customerGroup.Name
            $safeCustomerName = $customerName -replace '[\\/:*?"<>|\s]', '_'
            $customerData = $customerGroup.Group
            
            # Tab button
            $customerTabs += "<button class=`"tablinks`" onclick=`"openCustomer(event, '$safeCustomerName')`">$customerName</button>`n        "
            
            # Statistieken voor deze klant
            $totalAssignments = $customerData.Count
            $pimEligible = ($customerData | Where-Object { $_.AssignmentType -eq "Eligible" }).Count
            $pimActive = ($customerData | Where-Object { $_.AssignmentType -eq "Active" }).Count
            $permanentRoles = ($customerData | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
            $uniqueUsers = ($customerData | Where-Object { $_.UserType -eq "User" } | Select-Object -Unique PrincipalId).Count
            $globalAdmins = ($customerData | Where-Object { $_.RoleName -eq "Global Administrator" }).Count
            
            # PIM adoptie percentage
            $pimAdoption = if ($totalAssignments -gt 0) {
                [Math]::Round((($pimEligible + $pimActive) / $totalAssignments * 100), 1)
            } else { 0 }
            
            # Top 5 rollen voor deze klant
            $topRoles = $customerData | Group-Object RoleName | Sort-Object Count -Descending | Select-Object -First 5
            
            # Bouw tabel rows voor deze klant
            $tableRows = ""
            foreach ($assignment in $customerData) {
                $assignmentTypeColor = switch ($assignment.AssignmentType) {
                    "Eligible" { "color: #0066cc;" }
                    "Active" { "color: #28a745;" }
                    "Permanent" { "color: #dc3545;" }
                    default { "" }
                }
                
                $viaGroupText = if ($assignment.IsGroupMember -eq $true) { $assignment.ViaGroup } else { "Directe toewijzing" }
                $viaGroupColor = if ($assignment.IsGroupMember -eq $true) { "color: #6f42c1; font-style: italic;" } else { "color: #495057;" }
                
                $tableRows += @"
                <tr>
                    <td>$($assignment.DisplayName)</td>
                    <td>$($assignment.UserPrincipalName)</td>
                    <td>$($assignment.RoleName)</td>
                    <td style="$assignmentTypeColor"><strong>$($assignment.AssignmentType)</strong></td>
                    <td>$($assignment.UserType)</td>
                    <td>$($assignment.EmailAddress)</td>
                    <td>$($assignment.AccountEnabled)</td>
                    <td style="$viaGroupColor">$viaGroupText</td>
                    <td>$($assignment.Department)</td>
                    <td>$($assignment.JobTitle)</td>
                </tr>
"@
            }
            
            # Top rollen lijst
            $topRolesList = ""
            foreach ($role in $topRoles) {
                $topRolesList += "<li><strong>$($role.Name):</strong> $($role.Count) toewijzingen</li>"
            }
            
            # Customer content
            $customerTables += @"
    <div id="$safeCustomerName" class="tabcontent">
        <h3>$customerName - PIM & Role Assignment Overzicht</h3>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h4>Totaal Assignments</h4>
                <div class="stat-number">$totalAssignments</div>
            </div>
            <div class="stat-card eligible">
                <h4>PIM Eligible</h4>
                <div class="stat-number">$pimEligible</div>
            </div>
            <div class="stat-card active">
                <h4>PIM Active</h4>
                <div class="stat-number">$pimActive</div>
            </div>
            <div class="stat-card permanent">
                <h4>Permanent Rollen</h4>
                <div class="stat-number">$permanentRoles</div>
            </div>
            <div class="stat-card">
                <h4>Unieke Gebruikers</h4>
                <div class="stat-number">$uniqueUsers</div>
            </div>
            <div class="stat-card global-admin">
                <h4>Global Admins</h4>
                <div class="stat-number">$globalAdmins</div>
            </div>
            <div class="stat-card adoption">
                <h4>PIM Adoptie</h4>
                <div class="stat-number">$pimAdoption%</div>
            </div>
        </div>
        
        <div style="margin: 20px 0; background: #f8f9fa; padding: 15px; border-radius: 8px;">
            <h4 style="margin: 0 0 15px 0; color: #495057;"><i class="fa-solid fa-filter"></i> Filter Opties</h4>
            <div class="filter-buttons">
                <button class="filter-btn active" onclick="filterCustomerTable('$safeCustomerName', 'all')">
                    <i class="fa-solid fa-list"></i> Alle ($totalAssignments)
                </button>
                <button class="filter-btn eligible" onclick="filterCustomerTable('$safeCustomerName', 'eligible')">
                    <i class="fa-solid fa-clock"></i> PIM Eligible ($pimEligible)
                </button>
                <button class="filter-btn active-filter" onclick="filterCustomerTable('$safeCustomerName', 'active')">
                    <i class="fa-solid fa-check-circle"></i> PIM Active ($pimActive)
                </button>
                <button class="filter-btn permanent" onclick="filterCustomerTable('$safeCustomerName', 'permanent')">
                    <i class="fa-solid fa-exclamation-triangle"></i> Permanent ($permanentRoles)
                </button>
                <button class="filter-btn" onclick="filterCustomerTable('$safeCustomerName', 'users')">
                    <i class="fa-solid fa-users"></i> Alleen Gebruikers
                </button>
                <button class="filter-btn global-admin" onclick="filterCustomerTable('$safeCustomerName', 'globaladmins')">
                    <i class="fa-solid fa-crown"></i> Global Admins ($globalAdmins)
                </button>
            </div>
        </div>
        
        <div class="content-row">
            <div class="top-roles">
                <h4>Top 5 Rollen</h4>
                <ul>
                    $topRolesList
                </ul>
            </div>
        </div>
        
        <h4>Rol Toewijzingen <span id="filterLabel_$safeCustomerName" style="color: #6c757d; font-weight: normal;">(Alle toewijzingen)</span></h4>
        <table id="overviewTable_$safeCustomerName" class="display" style="width:100%">
            <thead>
                <tr>
                    <th>Naam</th>
                    <th>UPN</th>
                    <th>Rol</th>
                    <th>Type</th>
                    <th>User Type</th>
                    <th>Email</th>
                    <th>Enabled</th>
                    <th>Via Groep</th>
                    <th>Department</th>
                    <th>Job Title</th>
                </tr>
            </thead>
            <tbody>
                $tableRows
            </tbody>
        </table>
    </div>

"@
        }
        
        # Algemene statistieken
        $totalAllAssignments = $AllResults.Count
        $totalPimEligible = ($AllResults | Where-Object { $_.AssignmentType -eq "Eligible" }).Count
        $totalPimActive = ($AllResults | Where-Object { $_.AssignmentType -eq "Active" }).Count
        $totalPermanent = ($AllResults | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
        $totalUniqueUsers = ($AllResults | Where-Object { $_.UserType -eq "User" } | Select-Object -Unique PrincipalId).Count
        $totalGlobalAdmins = ($AllResults | Where-Object { $_.RoleName -eq "Global Administrator" }).Count
        $overallPimAdoption = if ($totalAllAssignments -gt 0) {
            [Math]::Round((($totalPimEligible + $totalPimActive) / $totalAllAssignments * 100), 1)
        } else { 0 }
        
        # DataTables script
        $dataTablesScript = @'
        function initializeDataTable(tableId) {
            if ($.fn.DataTable.isDataTable('#' + tableId)) {
                $('#' + tableId).DataTable().destroy();
            }
            $('#' + tableId).DataTable({
                pageLength: 25,
                order: [[2, 'asc']],
                columnDefs: [
                    { orderable: false, targets: [5, 7, 8] }
                ],
                language: {
                    search: "Zoeken:",
                    lengthMenu: "Toon _MENU_ entries",
                    info: "Toont _START_ tot _END_ van _TOTAL_ entries",
                    paginate: {
                        first: "Eerste",
                        last: "Laatste",
                        next: "Volgende",
                        previous: "Vorige"
                    }
                }
            });
        }
        
        $(document).ready(function() {
            // Initialiseer alle tabellen
            $('table[id^="overviewTable_"]').each(function() {
                initializeDataTable(this.id);
            });
            
            // Initialiseer wijzigingen tabel als deze bestaat
            if ($('#changesTable').length) {
                initializeDataTable('changesTable');
            }
        });
        
        // Filter functionaliteit
        function filterCustomerTable(customerName, filterType) {
            var tableId = 'overviewTable_';
            tableId = tableId + customerName;
            var tableObj = document.getElementById(tableId);
            if (!tableObj) return;
            
            var table = $(tableObj).DataTable();
            var labelId = 'filterLabel_';
            labelId = labelId + customerName;
            var label = document.getElementById(labelId);
            
            // Update active button
            var customerDiv = document.getElementById(customerName);
            var filterButtons = customerDiv.querySelectorAll('.filter-btn');
            filterButtons.forEach(function(btn) {
                btn.classList.remove('active');
            });
            event.target.classList.add('active');
            
            // Clear all existing searches first
            table.search('').columns().search('').draw();
            
            // Apply filter and update label
            switch(filterType) {
                case 'all':
                    // Show all rows - already cleared above
                    label.textContent = '(Alle toewijzingen)';
                    break;
                case 'eligible':
                    table.column(3).search('Eligible', false, false).draw();
                    label.textContent = '(PIM Eligible rollen)';
                    break;
                case 'active':
                    table.column(3).search('Active', false, false).draw();
                    label.textContent = '(PIM Active rollen)';
                    break;
                case 'permanent':
                    table.column(3).search('Permanent', false, false).draw();
                    label.textContent = '(Permanente rollen)';
                    break;
                case 'users':
                    table.column(4).search('User', false, false).draw();
                    label.textContent = '(Alleen gebruikers)';
                    break;
                case 'globaladmins':
                    table.column(2).search('Global Administrator', false, false).draw();
                    label.textContent = '(Global Administrators)';
                    break;
            }
        }
'@
        
        $lastRunDate = Get-Date -Format "dd-MM-yyyy HH:mm"
        $projectVersion = "1.0"
        $lastEditDate = Get-Date -Format "yyyy-MM-dd"
        
        # Bouw het complete HTML document
        $html = @"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>PIM & Role Assignment Dashboard</title>
    <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css"/>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
    <script>
    $dataTablesScript
    // Dark mode toggle
    document.addEventListener('DOMContentLoaded', function() {
        var btn = document.getElementById('darkModeToggle');
        var isDark = localStorage.getItem('darkMode') === 'true';
        
        function setTheme(useDark) {
            if (useDark) {
                document.body.classList.add('darkmode');
                if (btn) btn.innerHTML = '<i class="fa-solid fa-sun"></i> Light mode';
                localStorage.setItem('darkMode', 'true');
            } else {
                document.body.classList.remove('darkmode');
                if (btn) btn.innerHTML = '<i class="fa-solid fa-moon"></i> Dark mode';
                localStorage.setItem('darkMode', 'false');
            }
        }
        
        // Set initial theme
        setTheme(isDark);
        
        if (btn) {
            btn.addEventListener('click', function() {
                var currentlyDark = document.body.classList.contains('darkmode');
                setTheme(!currentlyDark);
            });
        }
        
        // Initialize first tab
        setTimeout(function() {
            var firstTab = document.getElementsByClassName("tablinks")[0];
            if (firstTab) firstTab.click();
        }, 100);
    });
    </script>
    <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f8f9fa; color: #212529; transition: background 0.3s, color 0.3s; }
    .container { max-width: 1400px; margin: auto; padding: 20px; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
    .header h1 { margin: 0; color: #0066cc; }
    
    /* Stats Grid */
    .global-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 20px; }
    .stat-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; border-left: 4px solid #0066cc; }
    .stat-card h4 { margin: 0 0 10px 0; font-size: 14px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
    .stat-card .stat-number { font-size: 28px; font-weight: bold; color: #333; }
    .stat-card.eligible { border-left-color: #0066cc; }
    .stat-card.eligible .stat-number { color: #0066cc; }
    .stat-card.active { border-left-color: #28a745; }
    .stat-card.active .stat-number { color: #28a745; }
    .stat-card.permanent { border-left-color: #dc3545; }
    .stat-card.permanent .stat-number { color: #dc3545; }
    .stat-card.global-admin { border-left-color: #ffc107; }
    .stat-card.global-admin .stat-number { color: #e68900; }
    .stat-card.adoption { border-left-color: #17a2b8; }
    .stat-card.adoption .stat-number { color: #17a2b8; }
    .stat-card.changes-new { border-left-color: #28a745; }
    .stat-card.changes-new .stat-number { color: #28a745; }
    .stat-card.changes-removed { border-left-color: #dc3545; }
    .stat-card.changes-removed .stat-number { color: #dc3545; }
    .stat-card.changes-modified { border-left-color: #ffc107; }
    .stat-card.changes-modified .stat-number { color: #e68900; }
    
    /* Content Layout */
    .content-row { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
    .top-roles { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .top-roles h4 { margin-top: 0; color: #333; }
    .top-roles ul { margin: 0; padding-left: 20px; }
    .top-roles li { margin-bottom: 8px; }
    
    /* Tabs */
    .tab { overflow: hidden; border-bottom: 2px solid #dee2e6; margin-bottom: 20px; }
    .tab button { background-color: #f8f9fa; float: left; border: none; outline: none; cursor: pointer; padding: 14px 20px; transition: 0.3s; font-size: 16px; margin-right: 4px; border-radius: 4px 4px 0 0; }
    .tab button:hover { background-color: #e9ecef; }
    .tab button.active { background-color: #0066cc; color: white; }
    .tabcontent { display: none; }
    
    /* Filter Buttons */
    .filter-buttons { display: flex; flex-wrap: wrap; gap: 10px; }
    .filter-btn { 
        background: white; 
        border: 2px solid #dee2e6; 
        padding: 8px 16px; 
        border-radius: 6px; 
        cursor: pointer; 
        font-size: 14px; 
        font-weight: 500;
        transition: all 0.3s;
        display: flex;
        align-items: center;
        gap: 6px;
    }
    .filter-btn:hover { 
        background: #f8f9fa; 
        border-color: #0066cc; 
        transform: translateY(-1px);
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .filter-btn.active { 
        background: #0066cc; 
        color: white; 
        border-color: #0066cc; 
    }
    .filter-btn.eligible { border-color: #0066cc; color: #0066cc; }
    .filter-btn.eligible:hover, .filter-btn.eligible.active { background: #0066cc; color: white; }
    .filter-btn.active-filter { border-color: #28a745; color: #28a745; }
    .filter-btn.active-filter:hover, .filter-btn.active-filter.active { background: #28a745; color: white; }
    .filter-btn.permanent { border-color: #dc3545; color: #dc3545; }
    .filter-btn.permanent:hover, .filter-btn.permanent.active { background: #dc3545; color: white; }
    .filter-btn.global-admin { border-color: #ffc107; color: #e68900; }
    .filter-btn.global-admin:hover, .filter-btn.global-admin.active { background: #ffc107; color: #212529; }
    
    /* Tables */
    table.dataTable { background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    table.dataTable thead th { background: #f8f9fa; color: #495057; font-weight: 600; padding: 12px; border-bottom: 2px solid #dee2e6; }
    table.dataTable tbody td { padding: 10px 12px; border-bottom: 1px solid #dee2e6; }
    table.dataTable tbody tr:hover { background-color: #f8f9fa; }
    
    /* Footer */
    .footer { margin-top: 40px; padding: 20px 0; border-top: 1px solid #dee2e6; text-align: center; color: #6c757d; font-size: 14px; }
    .footer a { color: #0066cc; text-decoration: none; }
    .footer a:hover { text-decoration: underline; }
    
    /* Dark mode styles */
    body.darkmode { background: #121212; color: #e0e0e0; }
    body.darkmode .container { background: #121212; }
    body.darkmode .stat-card { background: #1e1e1e; color: #e0e0e0; box-shadow: 0 2px 4px rgba(0,0,0,0.3); }
    body.darkmode .stat-card h4 { color: #b0b0b0; }
    body.darkmode .stat-card .stat-number { color: #e0e0e0; }
    body.darkmode .stat-card.eligible .stat-number { color: #4da6ff; }
    body.darkmode .stat-card.active .stat-number { color: #4dff4d; }
    body.darkmode .stat-card.permanent .stat-number { color: #ff4d4d; }
    body.darkmode .stat-card.global-admin .stat-number { color: #ffcc4d; }
    body.darkmode .stat-card.adoption .stat-number { color: #4dffff; }
    body.darkmode .stat-card.changes-new .stat-number { color: #4dff4d; }
    body.darkmode .stat-card.changes-removed .stat-number { color: #ff4d4d; }
    body.darkmode .stat-card.changes-modified .stat-number { color: #ffcc4d; }
    body.darkmode .top-roles { background: #1e1e1e; color: #e0e0e0; box-shadow: 0 2px 4px rgba(0,0,0,0.3); }
    body.darkmode .top-roles h4 { color: #e0e0e0; }
    body.darkmode .tab { border-bottom: 2px solid #333; }
    body.darkmode .tab button { background-color: #1e1e1e; color: #e0e0e0; }
    body.darkmode .tab button:hover { background-color: #333; }
    body.darkmode .tab button.active { background-color: #0066cc; color: white; }
    body.darkmode table.dataTable { background: #1e1e1e; box-shadow: 0 2px 4px rgba(0,0,0,0.3); }
    body.darkmode table.dataTable thead th { background: #333; color: #e0e0e0; border-bottom: 2px solid #555; }
    body.darkmode table.dataTable tbody td { border-bottom: 1px solid #333; color: #e0e0e0; }
    body.darkmode table.dataTable tbody tr:hover { background-color: #333; }
    body.darkmode .footer { border-top: 1px solid #333; color: #b0b0b0; }
    body.darkmode .footer a { color: #4da6ff; }
    
    /* Dark mode filter buttons */
    body.darkmode .filter-btn { background: #1e1e1e; border-color: #333; color: #e0e0e0; }
    body.darkmode .filter-btn:hover { background: #333; border-color: #4da6ff; }
    body.darkmode .filter-btn.active { background: #0066cc; color: white; border-color: #0066cc; }
    body.darkmode .filter-btn.eligible { border-color: #4da6ff; color: #4da6ff; }
    body.darkmode .filter-btn.eligible:hover, body.darkmode .filter-btn.eligible.active { background: #4da6ff; color: #121212; }
    body.darkmode .filter-btn.active-filter { border-color: #4dff4d; color: #4dff4d; }
    body.darkmode .filter-btn.active-filter:hover, body.darkmode .filter-btn.active-filter.active { background: #4dff4d; color: #121212; }
    body.darkmode .filter-btn.permanent { border-color: #ff4d4d; color: #ff4d4d; }
    body.darkmode .filter-btn.permanent:hover, body.darkmode .filter-btn.permanent.active { background: #ff4d4d; color: #121212; }
    body.darkmode .filter-btn.global-admin { border-color: #ffcc4d; color: #ffcc4d; }
    body.darkmode .filter-btn.global-admin:hover, body.darkmode .filter-btn.global-admin.active { background: #ffcc4d; color: #121212; }
    
    /* Button Styling */
    #darkModeToggle { 
        background: #0066cc; 
        color: white; 
        border: none; 
        padding: 10px 15px; 
        border-radius: 5px; 
        cursor: pointer; 
        font-size: 14px;
        transition: background 0.3s;
    }
    #darkModeToggle:hover { background: #0056b3; }
    body.darkmode #darkModeToggle { background: #ffc107; color: #000; }
    body.darkmode #darkModeToggle:hover { background: #e0a800; }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1><i class="fa-solid fa-shield-halved"></i> PIM & Role Assignment Dashboard</h1>
        <button id="darkModeToggle"><i class="fa-solid fa-moon"></i> Dark mode</button>
    </div>

    <p><i class="fa-solid fa-clock"></i> Laatst uitgevoerd op: $lastRunDate</p>
    
    <div class="global-stats">
        <div class="stat-card">
            <h4>Totaal Assignments</h4>
            <div class="stat-number">$totalAllAssignments</div>
        </div>
        <div class="stat-card eligible">
            <h4>PIM Eligible</h4>
            <div class="stat-number">$totalPimEligible</div>
        </div>
        <div class="stat-card active">
            <h4>PIM Active</h4>
            <div class="stat-number">$totalPimActive</div>
        </div>
        <div class="stat-card permanent">
            <h4>Permanent Rollen</h4>
            <div class="stat-number">$totalPermanent</div>
        </div>
        <div class="stat-card">
            <h4>Totaal Gebruikers</h4>
            <div class="stat-number">$totalUniqueUsers</div>
        </div>
        <div class="stat-card global-admin">
            <h4>Global Admins</h4>
            <div class="stat-number">$totalGlobalAdmins</div>
        </div>
        <div class="stat-card adoption">
            <h4>PIM Adoptie</h4>
            <div class="stat-number">$overallPimAdoption%</div>
        </div>
        $changesStats
    </div>

    <div class="tab">
        <button class="tablinks active" onclick="showOverview(event)">Overzicht</button>
        $changesTab
        $customerTabs
    </div>

    <div id="Overview" class="tabcontent" style="display:block;">
        <h3>Algemeen Overzicht - Alle Klanten</h3>
        <p>Dit dashboard toont een overzicht van alle PIM (Privileged Identity Management) en permanente rol-toewijzingen across alle tenants.</p>
        
        <div class="content-row">
            <div class="top-roles">
                <h4>Status Indicatoren</h4>
                <ul>
                    <li><strong style="color: #0066cc;">PIM Eligible:</strong> Gebruikers die een rol kunnen activeren</li>
                    <li><strong style="color: #28a745;">PIM Active:</strong> Gebruikers met tijdelijk geactiveerde rollen</li>
                    <li><strong style="color: #dc3545;">Permanent:</strong> Gebruikers met permanente rollen (RISICO)</li>
                    <li><strong style="color: #e68900;">Global Admins:</strong> Gebruikers met hoogste privileges</li>
                </ul>
            </div>
            <div class="top-roles">
                <h4>Security Aanbevelingen</h4>
                <ul>
                    <li>PIM Adoptie boven 90% is excellent</li>
                    <li>Permanent rollen minimaliseren</li>
                    <li>Global Admins onder 5 per tenant houden</li>
                    <li>Regelmatige access reviews uitvoeren</li>
                </ul>
            </div>
        </div>
    </div>

    $changesContent
    $customerTables
    
    <div class="footer">
        Powered by <strong>PIM & Role Assignment MultiTenant Dashboard</strong> 
        <span style="font-weight:normal;color:#888;">v$projectVersion $lastEditDate</span> 
        | Generated on $lastRunDate
    </div>
</div>

<script>
    // Tab functionaliteit
    function openCustomer(evt, customerName) {
        var i, tabcontent, tablinks;
        tabcontent = document.getElementsByClassName("tabcontent");
        for (i = 0; i < tabcontent.length; i++) {
            tabcontent[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName("tablinks");
        for (i = 0; i < tablinks.length; i++) {
            tablinks[i].className = tablinks[i].className.replace(" active", "");
        }
        document.getElementById(customerName).style.display = "block";
        evt.currentTarget.className += " active";
        
        // Initialiseer DataTable voor deze klant
        setTimeout(function() {
            initializeDataTable('overviewTable_' + customerName);
        }, 100);
    }
    
    function showOverview(evt) {
        var i, tabcontent, tablinks;
        tabcontent = document.getElementsByClassName("tabcontent");
        for (i = 0; i < tabcontent.length; i++) {
            tabcontent[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName("tablinks");
        for (i = 0; i < tablinks.length; i++) {
            tablinks[i].className = tablinks[i].className.replace(" active", "");
        }
        document.getElementById("Overview").style.display = "block";
        evt.currentTarget.className += " active";
    }
    
    function showChanges(evt) {
        var i, tabcontent, tablinks;
        tabcontent = document.getElementsByClassName("tabcontent");
        for (i = 0; i < tabcontent.length; i++) {
            tabcontent[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName("tablinks");
        for (i = 0; i < tablinks.length; i++) {
            tablinks[i].className = tablinks[i].className.replace(" active", "");
        }
        document.getElementById("Changes").style.display = "block";
        evt.currentTarget.className += " active";
        
        // Initialiseer DataTable voor wijzigingen
        setTimeout(function() {
            initializeDataTable('changesTable');
        }, 100);
    }
</script>
</body>
</html>
"@
        
        # Schrijf HTML naar bestand
        $htmlPath = Join-Path $ExportPath "${DatePrefix}_PIM_Role_Dashboard.html"
        Set-Content -Path $htmlPath -Value $html -Encoding UTF8
        
        return $htmlPath
    }
    catch {
        Write-Error "Fout bij genereren HTML dashboard: $($_.Exception.Message)"
        return $null
    }
}

# Functie om bestaande exports te laden voor rapport-only mode
function Get-ExistingExportData {
    param(
        [string]$ExportPath,
        [string]$DatePrefix
    )
    
    try {
        Write-Host "Zoeken naar bestaande export bestanden..." -ForegroundColor Cyan
        
        # Zoek naar het meest recente volledige rapport (sorteer op datum in bestandsnaam)
        $fullReportPattern = "*_All_Customers_Full_Report.csv"
        $allReports = Get-ChildItem -Path $ExportPath -Filter $fullReportPattern | Sort-Object { 
            # Extract datum uit bestandsnaam (YYYYMMDD)
            if ($_.Name -match '^(\d{8})_') { 
                [datetime]::ParseExact($matches[1], 'yyyyMMdd', $null) 
            } else { 
                $_.LastWriteTime 
            }
        } -Descending
        
        if ($allReports.Count -eq 0) {
            Write-Error "Geen bestaande export bestanden gevonden in: $ExportPath"
            Write-Host "Verwachte bestandsnaam patroon: ${fullReportPattern}" -ForegroundColor Yellow
            return $null
        }
        
        # Gebruik het meest recente rapport
        $latestReport = $allReports[0]
        Write-Host "✓ Gevonden meest recente export: $($latestReport.Name)" -ForegroundColor Green
        Write-Host "  Laatst gewijzigd: $($latestReport.LastWriteTime)" -ForegroundColor Gray
        
        # Laad de data
        $exportData = Import-Csv -Path $latestReport.FullName -Encoding UTF8
        Write-Host "✓ Export data geladen: $($exportData.Count) records" -ForegroundColor Green
        
        # Extract datum prefix van bestandsnaam voor consistentie
        $extractedDatePrefix = $latestReport.Name -replace '_All_Customers_Full_Report\.csv$', ''
        
        return @{
            Data = $exportData
            DatePrefix = $extractedDatePrefix
            SourceFile = $latestReport.FullName
            LastModified = $latestReport.LastWriteTime
        }
    }
    catch {
        Write-Error "Fout bij laden van bestaande export data: $($_.Exception.Message)"
        return $null
    }
}

# Hoofdscript
function Main {
    Write-Host "=== PIM & Permanent Role Users Report - Multi Tenant ===" -ForegroundColor Magenta
    Write-Host "Versie: $ProjectVersion" -ForegroundColor Gray
    Write-Host "Start tijd: $(Get-Date)" -ForegroundColor Gray
    
    if ($ReportOnly) {
        Write-Host "Mode: Alleen HTML rapport genereren (geen nieuwe data ophalen)" -ForegroundColor Yellow
    } else {
        Write-Host "Mode: Volledige data export en rapport generatie" -ForegroundColor Green
    }
    Write-Host ""
    
    # Laad configuratie
    $config = Get-ScriptConfig -ConfigFile $ConfigFile -OutputPathOverride $OutputPath
    
    # Initialiseer export folder
    $exportPath = Initialize-ExportFolder -Config $config
    if (-not $exportPath) {
        Write-Error "Kon export folder niet initialiseren. Script gestopt."
        exit 1
    }
    
    Write-Host "Export locatie: $exportPath" -ForegroundColor Cyan
    Write-Host ""
    
    # ReportOnly mode: laad bestaande data en genereer alleen HTML rapport
    if ($ReportOnly) {
        Write-Host "--- Rapport-Only Mode ---" -ForegroundColor Yellow
        
        # Probeer huidige datum prefix te gebruiken, of gebruik bestaande data
        $datePrefix = Get-Date -Format "yyyyMMdd"
        $existingData = Get-ExistingExportData -ExportPath $exportPath -DatePrefix $datePrefix
        
        if (-not $existingData) {
            Write-Error "Kon geen bestaande export data vinden. Voer eerst het script uit zonder -ReportOnly parameter."
            exit 1
        }
        
        $allResults = $existingData.Data
        $datePrefix = $existingData.DatePrefix
        
        Write-Host "✓ Bestaande data geladen van: $($existingData.LastModified)" -ForegroundColor Green
        Write-Host "✓ Aantal records: $($allResults.Count)" -ForegroundColor Green
        Write-Host "✓ Gebruikt datum prefix: $datePrefix" -ForegroundColor Green
        Write-Host ""
        
        # Detecteer wijzigingen ten opzichte van vorige export
        Write-Host "--- Wijzigingen detecteren ---" -ForegroundColor Yellow
        $changes = Compare-PIMExports -CurrentResults $allResults -ExportPath $exportPath -DatePrefix $datePrefix
        
        # Genereer HTML Dashboard
        Write-Host "--- HTML Dashboard genereren ---" -ForegroundColor Yellow
        $htmlPath = New-HTMLDashboard -AllResults $allResults -ExportPath $exportPath -DatePrefix $datePrefix -Config $config -Changes $changes
        
        if ($htmlPath) {
            Write-Host "✓ HTML Dashboard gegenereerd: $htmlPath" -ForegroundColor Green
            
            # Open HTML rapport automatisch als geconfigureerd
            if ($config.ReportSettings.AutoOpenHTMLReport) {
                try {
                    if ((Test-Path $htmlPath -PathType Leaf) -and ($htmlPath.ToLower().EndsWith(".html"))) {
                        Write-Host "📖 HTML rapport wordt geopend in standaard browser..." -ForegroundColor Cyan
                        Start-Process $htmlPath
                    }
                } catch {
                    Write-Warning "Kon HTML rapport niet automatisch openen: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Error "HTML Dashboard kon niet worden gegenereerd"
            exit 1
        }
        
        Write-Host ""
        Write-Host "=== Rapport-Only Mode Voltooid ===" -ForegroundColor Green
        Write-Host "HTML Dashboard: $htmlPath" -ForegroundColor Cyan
        Write-Host "Gebaseerd op data van: $($existingData.LastModified)" -ForegroundColor Gray
        Write-Host "Eind tijd: $(Get-Date)" -ForegroundColor Gray
        return
    }
    
    # Normale mode: haal nieuwe data op
    # Lijst van benodigde modules
    $RequiredModules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Identity.Governance", 
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.Users",
        "Microsoft.Graph.Groups",
        "Microsoft.Graph.Applications"
    )
    
    # Installeer en importeer benodigde modules
    Install-RequiredModules -ModuleNames $RequiredModules
    
    # Lees credentials
    $credentialsFile = "credentials.json"
    if (-not (Test-Path $credentialsFile)) {
        Write-Error "Credentials bestand niet gevonden: $credentialsFile"
        exit 1
    }
    
    try {
        $credentialsData = Get-Content $credentialsFile -Raw | ConvertFrom-Json
        
        # Check if credentials are wrapped in LoginCredentials object
        if ($credentialsData.LoginCredentials) {
            $credentials = $credentialsData.LoginCredentials
        } else {
            $credentials = $credentialsData
        }
        
        Write-Host "✓ Credentials bestand gelezen. Aantal tenants: $($credentials.Count)" -ForegroundColor Green
    }
    catch {
        Write-Error "Kon credentials bestand niet laden: $($_.Exception.Message)"
        exit 1
    }
    
    # Verzamel alle resultaten
    $allResults = @()
    $successfulTenants = 0
    $failedTenants = 0
    
    foreach ($tenant in $credentials) {
        Write-Host ""
        Write-Host "--- Verwerken van $($tenant.customername) ---" -ForegroundColor White
        
        # Verbind met tenant (handle both naming conventions)
        $clientId = if ($tenant.ClientId) { $tenant.ClientId } else { $tenant.ClientID }
        $clientSecret = if ($tenant.ClientSecret) { $tenant.ClientSecret } else { $tenant.Secret }
        $tenantId = if ($tenant.TenantId) { $tenant.TenantId } else { $tenant.TenantID }
        $customerName = if ($tenant.CustomerName) { $tenant.CustomerName } else { $tenant.customername }
        
        $connected = Connect-MicrosoftGraph -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
        
        if ($connected) {
            # Haal PIM rol-toewijzingen op
            $pimAssignments = Get-PIMRoleAssignments -TenantId $tenantId -CustomerName $customerName
            $allResults += $pimAssignments
            
            # Haal permanente (non-PIM) rol-toewijzingen op
            $permanentAssignments = Get-PermanentRoleAssignments -TenantId $tenantId -CustomerName $customerName
            $allResults += $permanentAssignments
            
            $successfulTenants++
            
            # Disconnect voor de volgende tenant
            try {
                Disconnect-MgGraph | Out-Null
            }
            catch { }
        }
        else {
            $failedTenants++
            Write-Error "Overslaan van $customerName vanwege verbindingsfouten"
        }
    }
    
    # Genereer rapporten
    Write-Host ""
    Write-Host "=== Rapporten genereren ===" -ForegroundColor Magenta
    
    # Datum voor bestandsnamen (zonder timestamp)
    $datePrefix = Get-Date -Format "yyyyMMdd"
    
    # Genereer rapporten per klant/tenant
    Write-Host ""
    Write-Host "--- Per-klant rapporten ---" -ForegroundColor Yellow
    $customerResults = $allResults | Group-Object Customer
    
    foreach ($customerGroup in $customerResults) {
        $customerName = $customerGroup.Name
        $customerData = $customerGroup.Group
        $safeCustomerName = $customerName -replace '[\\/:*?"<>|]', '_'  # Vervang ongeldige bestandsnaam karakters
        
        Write-Host "  - Genereren rapport voor: $customerName" -ForegroundColor Cyan
        
        # Volledig rapport per klant
        $customerFullPath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_Full_Report.csv"
        $customerData | Export-Csv -Path $customerFullPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        
        # Alleen gebruikers per klant
        $customerUsersPath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_Users_Only.csv"
        $customerData | Where-Object { $_.UserType -eq "User" } | Export-Csv -Path $customerUsersPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        
        # PIM Eligible per klant
        $customerEligiblePath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_PIM_Eligible.csv"
        $customerData | Where-Object { $_.AssignmentType -eq "Eligible" } | Export-Csv -Path $customerEligiblePath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        
        # PIM Active per klant
        $customerActivePath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_PIM_Active.csv"
        $customerData | Where-Object { $_.AssignmentType -eq "Active" } | Export-Csv -Path $customerActivePath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        
        # Permanente rollen per klant
        $customerPermanentPath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_Permanent_Roles.csv"
        $customerData | Where-Object { $_.AssignmentType -eq "Permanent" } | Export-Csv -Path $customerPermanentPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        
        # High-privilege gebruikers per klant
        $customerHighPrivData = $customerData | Where-Object { $_.RoleName -in $highPrivilegeRoles }
        if ($customerHighPrivData.Count -gt 0) {
            $customerHighPrivPath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_High_Privilege.csv"
            $customerHighPrivData | Export-Csv -Path $customerHighPrivPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        }
        
        # Klant samenvatting
        $customerSummary = [PSCustomObject]@{
            Customer = $customerName
            TotalAssignments = $customerData.Count
            PIMEligible = ($customerData | Where-Object { $_.AssignmentType -eq "Eligible" }).Count
            PIMActive = ($customerData | Where-Object { $_.AssignmentType -eq "Active" }).Count
            PermanentRoles = ($customerData | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
            UniqueUsers = ($customerData | Where-Object { $_.UserType -eq "User" } | Select-Object -Unique PrincipalId).Count
            ServicePrincipals = ($customerData | Where-Object { $_.UserType -eq "ServicePrincipal" }).Count
            Groups = ($customerData | Where-Object { $_.UserType -eq "Group" }).Count
            GlobalAdmins = ($customerData | Where-Object { $_.RoleName -eq "Global Administrator" }).Count
            HighPrivilegeUsers = ($customerData | Where-Object { $_.RoleName -in $highPrivilegeRoles }).Count
            TopRoles = ($customerData | Group-Object RoleName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join "; "
            PIMAdoptionPercentage = if ($customerData.Count -gt 0) {
                $pimCount = ($customerData | Where-Object { $_.AssignmentType -in @("Eligible","Active") }).Count
                [Math]::Round(($pimCount / $customerData.Count * 100), 1)
            } else { 0 }
        }
        
        $customerSummaryPath = Join-Path $exportPath "${datePrefix}_${safeCustomerName}_Summary.csv"
        $customerSummary | Export-Csv -Path $customerSummaryPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        
        Write-Host "    ✓ $($customerData.Count) assignments voor $customerName" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "--- Gecombineerde rapporten (alle klanten) ---" -ForegroundColor Yellow
    
    # Volledig rapport
    $fullReportPath = Join-Path $exportPath "${datePrefix}_All_Customers_Full_Report.csv"
    $allResults | Export-Csv -Path $fullReportPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ Volledig rapport (PIM + Permanent) opgeslagen: $fullReportPath" -ForegroundColor Green
    
    # Alleen gebruikers (geen service principals of groepen)
    $usersOnlyPath = Join-Path $exportPath "${datePrefix}_All_Customers_Users_Only.csv"
    $allResults | Where-Object { $_.UserType -eq "User" } | Export-Csv -Path $usersOnlyPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ Gebruikers-only rapport opgeslagen: $usersOnlyPath" -ForegroundColor Green
    
    # PIM Eligible assignments
    $eligiblePath = Join-Path $exportPath "${datePrefix}_All_Customers_PIM_Eligible.csv"
    $allResults | Where-Object { $_.AssignmentType -eq "Eligible" } | Export-Csv -Path $eligiblePath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ PIM Eligible gebruikers rapport opgeslagen: $eligiblePath" -ForegroundColor Green
    
    # PIM Active assignments
    $activePath = Join-Path $exportPath "${datePrefix}_All_Customers_PIM_Active.csv"
    $allResults | Where-Object { $_.AssignmentType -eq "Active" } | Export-Csv -Path $activePath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ PIM Active gebruikers rapport opgeslagen: $activePath" -ForegroundColor Green
    
    # Permanent assignments (non-PIM rollen)
    $permanentPath = Join-Path $exportPath "${datePrefix}_All_Customers_Permanent_Roles.csv"
    $allResults | Where-Object { $_.AssignmentType -eq "Permanent" } | Export-Csv -Path $permanentPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ Permanente rol gebruikers rapport opgeslagen: $permanentPath" -ForegroundColor Green
    
    # Vergelijking: PIM vs Permanent
    $comparisonPath = Join-Path $exportPath "${datePrefix}_All_Customers_PIM_vs_Permanent_Comparison.csv"
    $allResults | Select-Object Customer, DisplayName, UserPrincipalName, RoleName, AssignmentType, UserType, EmailAddress, IsPIMManaged | Export-Csv -Path $comparisonPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ PIM vs Permanent vergelijking opgeslagen: $comparisonPath" -ForegroundColor Green
    
    # High-privilege rollen
    $highPrivilegeRoles = @(
        "Global Administrator",
        "Privileged Role Administrator", 
        "User Administrator",
        "Exchange Administrator",
        "SharePoint Administrator",
        "Security Administrator",
        "Conditional Access Administrator",
        "Application Administrator",
        "Cloud Application Administrator",
        "Privileged Authentication Administrator"
    )
    
    $highPrivUsers = $allResults | Where-Object { $_.RoleName -in $highPrivilegeRoles }
    if ($highPrivUsers.Count -gt 0) {
        $highPrivPath = Join-Path $exportPath "${datePrefix}_All_Customers_High_Privilege.csv"
        $highPrivUsers | Export-Csv -Path $highPrivPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
        Write-Host "✓ High-privilege gebruikers rapport opgeslagen: $highPrivPath" -ForegroundColor Green
    }
    
    # Samenvatting rapport per tenant
    $summaryReport = $allResults | Group-Object Customer | ForEach-Object {
        $pimEligible = ($_.Group | Where-Object { $_.AssignmentType -eq "Eligible" }).Count
        $pimActive = ($_.Group | Where-Object { $_.AssignmentType -eq "Active" }).Count
        $permanent = ($_.Group | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
        
        [PSCustomObject]@{
            Customer = $_.Name
            TotalAssignments = $_.Count
            PIMEligible = $pimEligible
            PIMActive = $pimActive
            PermanentRoles = $permanent
            UniqueUsers = ($_.Group | Where-Object { $_.UserType -eq "User" } | Select-Object -Unique PrincipalId).Count
            ServicePrincipals = ($_.Group | Where-Object { $_.UserType -eq "ServicePrincipal" }).Count
            Groups = ($_.Group | Where-Object { $_.UserType -eq "Group" }).Count
            GlobalAdmins = ($_.Group | Where-Object { $_.RoleName -eq "Global Administrator" }).Count
            HighPrivilegeUsers = ($_.Group | Where-Object { $_.RoleName -in $highPrivilegeRoles }).Count
            PIMvsPermRatio = if ($permanent -gt 0) { 
                [Math]::Round((($pimEligible + $pimActive) / $permanent), 2)
            } else { 
                if (($pimEligible + $pimActive) -gt 0) { "∞" } else { "N/A" }
            }
            PIMAdoptionPercentage = if ($_.Count -gt 0) {
                [Math]::Round((($pimEligible + $pimActive) / $_.Count * 100), 1)
            } else { 0 }
        }
    }
    
    $summaryPath = Join-Path $exportPath "${datePrefix}_All_Customers_Summary.csv"
    $summaryReport | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding $config.ReportSettings.FileEncoding
    Write-Host "✓ Rol toewijzing samenvatting rapport opgeslagen: $summaryPath" -ForegroundColor Green
    
    # Genereer HTML Dashboard
    Write-Host ""
    Write-Host "--- HTML Dashboard genereren ---" -ForegroundColor Yellow
    
    # Detecteer wijzigingen ten opzichte van vorige export
    $changes = Compare-PIMExports -CurrentResults $allResults -ExportPath $exportPath -DatePrefix $datePrefix
    
    if ($config.ReportSettings.GenerateHTMLDashboard) {
        $htmlPath = New-HTMLDashboard -AllResults $allResults -ExportPath $exportPath -DatePrefix $datePrefix -Config $config -Changes $changes
        if ($htmlPath) {
            Write-Host "✓ HTML Dashboard gegenereerd: $htmlPath" -ForegroundColor Green
            
            # Open HTML rapport automatisch als geconfigureerd
            if ($config.ReportSettings.AutoOpenHTMLReport) {
                try {
                    if ((Test-Path $htmlPath -PathType Leaf) -and ($htmlPath.ToLower().EndsWith(".html"))) {
                        Write-Host "📖 HTML rapport wordt geopend in standaard browser..." -ForegroundColor Cyan
                        Start-Process $htmlPath
                    } else {
                        Write-Warning "Het HTML rapportbestand bestaat niet: $htmlPath"
                    }
                } catch {
                    Write-Warning "Kon HTML rapport niet automatisch openen: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Warning "HTML Dashboard kon niet worden gegenereerd"
        }
    } else {
        Write-Host "HTML Dashboard generatie uitgeschakeld in config.json" -ForegroundColor Gray
    }
    
    # Eindstatistieken
    Write-Host ""
    Write-Host "=== Eindstatistieken ===" -ForegroundColor Magenta
    Write-Host "Succesvol verwerkte tenants: $successfulTenants" -ForegroundColor Green
    Write-Host "Gefaalde tenants: $failedTenants" -ForegroundColor $(if ($failedTenants -gt 0) { "Red" } else { "Green" })
    Write-Host ""
    Write-Host "=== Rol Toewijzing Overzicht ===" -ForegroundColor Cyan
    Write-Host "Totaal aantal rol toewijzingen: $($allResults.Count)" -ForegroundColor Cyan
    Write-Host "  - PIM Eligible: $(($allResults | Where-Object { $_.AssignmentType -eq 'Eligible' }).Count)" -ForegroundColor Yellow
    Write-Host "  - PIM Active: $(($allResults | Where-Object { $_.AssignmentType -eq 'Active' }).Count)" -ForegroundColor Yellow
    Write-Host "  - Permanente rollen: $(($allResults | Where-Object { $_.AssignmentType -eq 'Permanent' }).Count)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Totaal aantal unieke gebruikers: $(($allResults | Where-Object { $_.UserType -eq 'User' } | Select-Object -Unique PrincipalId).Count)" -ForegroundColor Cyan
    
    # PIM vs Permanent ratio
    $pimCount = ($allResults | Where-Object { $_.AssignmentType -in @("Eligible","Active") }).Count
    $permanentCount = ($allResults | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
    if ($permanentCount -gt 0) {
        $ratio = [Math]::Round(($pimCount / $permanentCount), 2)
        Write-Host "PIM vs Permanent ratio: $ratio (Hoger is beter - meer PIM gebruik)" -ForegroundColor $(if ($ratio -gt 1) { "Green" } elseif ($ratio -gt 0.5) { "Yellow" } else { "Red" })
    }
    
    # PIM adoptie percentage
    if ($allResults.Count -gt 0) {
        $pimAdoption = [Math]::Round(($pimCount / $allResults.Count * 100), 1)
        Write-Host "PIM adoptie percentage: $pimAdoption% (Hoger is beter)" -ForegroundColor $(if ($pimAdoption -gt 75) { "Green" } elseif ($pimAdoption -gt 50) { "Yellow" } else { "Red" })
    }
    
    if ($allResults.Count -gt 0) {
        Write-Host ""
        Write-Host "Top rollen per aantal toewijzingen:" -ForegroundColor Yellow
        $allResults | Group-Object RoleName | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            $pimCount = ($_.Group | Where-Object { $_.AssignmentType -in @("Eligible","Active") }).Count
            $permCount = ($_.Group | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
            Write-Host "  - $($_.Name): $($_.Count) toewijzingen (PIM: $pimCount, Permanent: $permCount)" -ForegroundColor White
        }
        
        $globalAdmins = $allResults | Where-Object { $_.RoleName -eq "Global Administrator" -and $_.UserType -eq "User" }
        if ($globalAdmins.Count -gt 0) {
            Write-Host "`nGlobal Administrators per tenant:" -ForegroundColor Red
            $globalAdmins | Group-Object Customer | ForEach-Object {
                $eligible = ($_.Group | Where-Object { $_.AssignmentType -eq "Eligible" }).Count
                $active = ($_.Group | Where-Object { $_.AssignmentType -eq "Active" }).Count
                $permanent = ($_.Group | Where-Object { $_.AssignmentType -eq "Permanent" }).Count
                Write-Host "  - $($_.Name): $($_.Count) Global Admins (Eligible: $eligible, Active: $active, Permanent: $permanent)" -ForegroundColor White
            }
        }
    }
    
    Write-Host ""
    Write-Host "Eind tijd: $(Get-Date)" -ForegroundColor Gray
}

# Start het script
Main
