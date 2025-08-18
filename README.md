# PIM & Permanent Role Users Report - Multi Tenant

Een uitgebreide PowerShell-oplossing voor het analyseren van Privileged Identity Management (PIM) en permanente roltoewijzingen in meerdere Microsoft 365/Azure AD tenants.

## 📋 Overzicht

Dit script biedt gedetailleerde rapportage over:### ReportOnly Vereisten

- Minimaal één bestaande export (via normale uitvoering)
- `*_All_Customers_Full_Report.csv` bestand in export directory
- Geldige `config.json` voor HTML instellingen

## 💾 Backup Functionaliteit

### Automatische Backups

Het script biedt automatische backup functionaliteit voor:

- **Export bestanden** - Alle CSV rapporten worden gecomprimeerd
- **Configuratie bestanden** - config.json en credentials.json worden beveiligd
- **Retention beleid** - Automatische opschoning van oude backups

### Backup Configuratie

```json
"BackupSettings": {
    "EnableBackup": true,
    "BackupRoot": "backups",
    "ExportBackupSubfolder": "exports", 
    "ConfigBackupSubfolder": "config",
    "EnableExportBackup": true,
    "EnableConfigBackup": true,
    "ExportBackupRetention": 5,
    "ConfigBackupRetention": 3
}
```

### Backup Instellingen

- **`EnableBackup`** - Hoofdschakelaar voor backup functionaliteit
- **`BackupRoot`** - Root directory voor alle backups (standaard: "backups")
- **`ExportBackupSubfolder`** - Subdirectory voor export backups
- **`ConfigBackupSubfolder`** - Subdirectory voor configuratie backups
- **`EnableExportBackup`** - Export bestanden backuppen (true/false)
- **`EnableConfigBackup`** - Configuratie bestanden backuppen (true/false)
- **`ExportBackupRetention`** - Aantal export backups te behouden (standaard: 5)
- **`ConfigBackupRetention`** - Aantal config backups te behouden (standaard: 3)

### Backup Voordelen

✅ **Automatisch** - Backups worden automatisch aangemaakt na elke run

✅ **Retention** - Oude backups worden automatisch verwijderd

✅ **Gecomprimeerd** - ZIP formaat voor efficiënte opslag

✅ **Timestamped** - Duidelijke naamgeving met datum/tijd

✅ **Gefilterd** - Alleen relevante bestanden worden gebackupt

## 🔄 Wijzigingsdetectie

### Automatische Change Detection

Het script bevat een geavanceerd systeem voor het detecteren van wijzigingen in roltoewijzingen tussen verschillende uitvoeringen. Dit helpt bij het monitoren van security changes en compliance tracking.

### Intelligente PIM Filtering

Een belangrijk kenmerk van de wijzigingsdetectie is dat **normale PIM-activaties niet worden gerapporteerd als wijzigingen**:

- **Eligible → Active**: Wanneer een gebruiker een PIM rol activeert
- **Active → Eligible**: Wanneer een PIM rol weer deactiveert/verloopt
- **Eligible → Eligible**: Hernieuwing van eligible status

Deze overgangen worden automatisch uitgefilterd omdat ze deel uitmaken van normale PIM-operaties en niet wijzen op structurele veranderingen in de roltoewijzingen.

### Wel Gerapporteerde Wijzigingen

Het systeem rapporteert wel de volgende belangrijke wijzigingen:

- **Nieuwe roltoewijzingen**: Volledig nieuwe toegang voor gebruikers
- **Verwijderde roltoewijzingen**: Intrekking van toegang
- **Permanente rol wijzigingen**: Veranderingen in permanent toegewezen rollen
- **Groepslidmaatschap veranderingen**: Wijzigingen via security groups
- **Assignment Type wijzigingen**: Van Permanent naar PIM of vice versa

### Change Report Output

```csv
# Voorbeeld uitvoer wijzigingsrapport
User,Role,ChangeType,PreviousState,CurrentState,Tenant,Timestamp
john.doe@company.com,Global Administrator,NEW,None,Permanent,Customer1,2025-08-18T10:30:00
jane.smith@company.com,Security Administrator,REMOVED,PIM Eligible,None,Customer2,2025-08-18T10:30:00
```

### Configuratie

Wijzigingsdetectie is automatisch ingeschakeld en vereist geen extra configuratie. Het systeem:

- Vergelijkt automatisch met de vorige export
- Genereert een `Changes_Report.csv` bestand
- Toont samenvattingsstatistieken in de console
- Integreert change information in het HTML dashboard

### Wijzigingsdetectie Voordelen

✅ **Security Monitoring** - Detecteert ongeautoriseerde wijzigingen

✅ **Compliance Tracking** - Audit trail voor roltoewijzingen

✅ **Intelligent Filtering** - Onderscheidt tussen operationele en structurele wijzigingen

✅ **Automated Reporting** - Geen handmatige vergelijking nodig

✅ **Historical Context** - Behoudt overzicht van veranderingen over tijd

### Backup Structuur

```text
backups/
├── exports/
│   ├── exports-20250817_200746.zip
│   ├── exports-20250816_154321.zip
│   └── ...
└── config/
    ├── config-20250817_200752.zip
    ├── config-20250816_154325.zip
    └── ...
```

## 🔧 Troubleshooting*PIM rol-toewijzingen** (Eligible en Active)'

- **Permanente roltoewijzingen** (niet via PIM)
- **Groepslidmaatschap** voor privileged rollen
- **Multi-tenant ondersteuning** voor MSP's en grote organisaties
- **HTML Dashboard** met moderne UI/UX
- **Uitgebreide CSV exports** per klant en gecombineerd

## ✨ Functies

### 🔍 Uitgebreide Analyse

- **PIM Eligible**: Gebruikers die rollen kunnen activeren
- **PIM Active**: Momenteel geactiveerde rollen
- **Permanent**: Permanente roltoewijzingen (security risk)
- **Groepsleden**: Automatische detectie van gebruikers via groepslidmaatschap
- **Service Principals**: Inclusief applicatie-identiteiten

### 📊 Modern HTML Dashboard

- **Dark/Light mode** toggle met persistentie
- **Responsive design** voor alle apparaten
- **Interactieve tabellen** met DataTables
- **Per-klant tabs** voor gedetailleerde analyse
- **Real-time statistieken** en grafieken
- **Security aanbevelingen** en best practices

### 📄 Uitgebreide Rapportage

- **Per-klant CSV exports** met nieuwe naamconventie
- **Gecombineerde rapporten** voor alle tenants
- **Gefilterde rapporten** (Users Only, PIM Eligible, etc.)
- **High-privilege gebruikers** rapportage
- **Vergelijkingsrapporten** PIM vs Permanent

### 🏢 Multi-Tenant Ondersteuning

- **Meerdere tenants** in één run
- **Flexibele credential structuur** ondersteuning
- **Foutafhandeling** per tenant
- **Gedetailleerde logging** met voortgangsindicaties

## 🚀 Installatie

### Vereisten

- **PowerShell 5.1** of hoger
- **Microsoft Graph PowerShell modules** (automatisch geïnstalleerd)
- **Azure AD App Registration** met juiste permissies

### Benodigde Permissies

Configureer de volgende Microsoft Graph API permissies in Azure AD:

```text
RoleManagement.Read.Directory
Directory.Read.All
User.Read.All
Group.Read.All
Application.Read.All
```

### Setup

1. **Clone het repository**:

   ```bash
   git clone https://github.com/scns/Privileged-Users-Report-MultiTenant.git
   cd Privileged-Users-Report-MultiTenant
   ```

2. **Configureer credentials**:

   ```bash
   # Kopieer template bestanden
   copy _credentials.json credentials.json
   copy _config.json config.json
   
   # Bewerk credentials.json met jouw tenant gegevens
   notepad credentials.json
   ```

3. **Run het script**:

   ```powershell
   .\Get-PIMUsers.ps1
   ```

## ⚙️ Configuratie

### credentials.json

Maak een `credentials.json` bestand met tenant informatie:

```json
{
    "LoginCredentials": [
        {
            "customername": "Customer1",
            "ClientID": "your-app-id-here",
            "Secret": "your-client-secret-here",
            "TenantID": "your-tenant-id-here"
        },
        {
            "customername": "Customer2", 
            "ClientID": "your-app-id-here",
            "Secret": "your-client-secret-here",
            "TenantID": "your-tenant-id-here"
        }
    ]
}
```

> 💡 **Tip**: Gebruik het meegeleverde `_credentials.json` template bestand

### config.json (Optioneel)

Pas rapportage-instellingen aan:

```json
{
    "ExportSettings": {
        "OutputFolder": "exports",
        "CreateDateSubfolders": false,
        "ArchiveOldReports": true,
        "MaxReportsToKeep": 10
    },
    "ReportSettings": {
        "IncludeTimestamp": false,
        "FileEncoding": "UTF8",
        "DateFormat": "yyyyMMdd",
        "IncludeServicePrincipals": true
    },
    "HTMLSettings": {
        "GenerateHTMLDashboard": true,
        "AutoOpenHTMLReport": true
    },
    "BackupSettings": {
        "EnableBackup": true,
        "BackupRoot": "backups",
        "ExportBackupSubfolder": "exports",
        "ConfigBackupSubfolder": "config",
        "EnableExportBackup": true,
        "EnableConfigBackup": true,
        "ExportBackupRetention": 5,
        "ConfigBackupRetention": 3
    }
}
```

> 💡 **Tip**: Gebruik het meegeleverde `_config.json` template bestand

## 🖥️ Gebruik

### Basis Gebruik

```powershell
# Standaard configuratie
.\Get-PIMUsers.ps1

# Custom configuratie
.\Get-PIMUsers.ps1 -ConfigFile "custom-config.json" -OutputPath "C:\Reports"
```

### Parameters

- `-ConfigFile`: Pad naar configuratiebestand (standaard: config.json)
- `-OutputPath`: Output directory (overschrijft config.json)
- `-ReportOnly`: Genereer alleen HTML rapport uit bestaande exports zonder nieuwe data op te halen

### Gebruik voorbeelden

```powershell
# Normale uitvoering - haalt nieuwe data op en genereert rapporten
.\Get-PIMUsers.ps1

# Met aangepaste configuratie
.\Get-PIMUsers.ps1 -ConfigFile "custom-config.json"

# Met aangepast output pad
.\Get-PIMUsers.ps1 -OutputPath "C:\Reports"

# Alleen HTML rapport genereren uit bestaande data
.\Get-PIMUsers.ps1 -ReportOnly

# Combinatie van parameters
.\Get-PIMUsers.ps1 -ConfigFile "custom-config.json" -ReportOnly
```

## 📁 Output Bestanden

### Naamconventie

Alle bestanden gebruiken het format: `YYYYMMDD_Customer_ReportType.csv`

### Per Klant

- `20250816_Customer1_Full_Report.csv` - Alle rol-toewijzingen
- `20250816_Customer1_Users_Only.csv` - Alleen gebruikers
- `20250816_Customer1_PIM_Eligible.csv` - PIM Eligible rollen
- `20250816_Customer1_PIM_Active.csv` - Actieve PIM rollen
- `20250816_Customer1_Permanent_Roles.csv` - Permanente rollen
- `20250816_Customer1_Summary.csv` - Samenvattingsrapport

### Gecombineerde Rapporten

- `20250816_All_Customers_Full_Report.csv` - Alle klanten gecombineerd
- `20250816_All_Customers_High_Privilege.csv` - High-privilege rollen
- `20250816_All_Customers_PIM_vs_Permanent_Comparison.csv` - Vergelijking
- `PIM_Role_Dashboard.html` - **Interactief HTML Dashboard**

## 🎨 HTML Dashboard Features

### 📱 Modern Interface

- **Responsive design** - Werkt op desktop, tablet, en mobile
- **Dark/Light mode** - Automatische thema-persistentie
- **FontAwesome iconen** - Professionele UI elementen
- **Moderne kleuren** - Visueel aantrekkelijke statistieken

### 📊 Interactieve Elementen

- **DataTables** - Sorteerbare, doorzoekbare tabellen
- **Customer tabs** - Gefocusseerde analyse per klant
- **Real-time filters** - Dynamische data filtering
- **Responsive statistieken** - Automatisch aangepaste lay-out
- **Clickable filter buttons** - Directe filtering per rol type

#### 🎯 Clickable Filter Buttons

Elke customer tab bevat intelligente filter buttons voor snelle data analyse:

- **🗂️ Alle** - Toont alle rol-toewijzingen (totaal aantal tussen haakjes)
- **🔵 Eligible** - Filtert alleen PIM Eligible rollen die geactiveerd kunnen worden
- **🟢 Active** - Toont alleen momenteel actieve PIM rollen
- **🔴 Permanent** - Toont permanente rollen (security risk - direct toegewezen)
- **👤 Users** - Filtert alleen gebruikers (exclusief service principals)
- **⚡ Global Admins** - Toont alleen Global Administrator rollen

**Functionaliteit:**

- **Direct klikken** - Geen reload nodig, client-side filtering
- **Visual feedback** - Actieve filter wordt gemarkeerd
- **Aantal indicatie** - Elk filter toont het aantal resultaten
- **Snelle navigatie** - Schakel moeiteloos tussen verschillende views
- **Kleurcodering** - Visuele identificatie van rol types

### 🔍 Data Visualisatie

- **Security status indicatoren** - Kleurgecodeerde risico's
- **PIM adoptie percentage** - Compliance tracking
- **Top rollen overzicht** - Meest gebruikte privileges
- **Groepslidmaatschap indicaties** - Via groep of direct toegewezen

## 🔒 Security Features

### 🛡️ Risk Assessment

- **Permanent rol detectie** - Identificeert security risico's
- **Global Admin tracking** - Monitort hoogste privileges
- **PIM adoptie metrics** - Compliance percentage
- **Groepsleden analyse** - Verborgen toegang via groepen

### 📈 Best Practices

- **PIM adoptie > 90%** wordt aanbevolen
- **Minimaliseer permanent rollen** voor betere security
- **Global Admins < 5 per tenant** als guideline
- **Regelmatige access reviews** voor compliance

## � ReportOnly Mode

### Wanneer gebruiken?

De `-ReportOnly` parameter is handig in deze situaties:

- **Snel HTML dashboard regenereren** - Zonder wachten op API calls
- **Verschillende visualisaties** - Experimenteren met configuratie wijzigingen
- **Demo doeleinden** - Presenteren van bestaande data
- **Troubleshooting HTML** - Testen van dashboard wijzigingen
- **Offline analyse** - Werken met eerder opgehaalde data

### Voordelen

- ⚡ **Snelheid** - Geen API authenticatie of netwerkverkeer nodig
- 🔄 **Vergelijking** - Automatische detectie van wijzigingen tussen exports
- 💾 **Efficiëntie** - Hergebruik van bestaande data
- 🎨 **Flexibiliteit** - Makkelijk experimenteren met rapportage

### ReportOnly Vereisten

- Minimaal één bestaande export (via normale uitvoering)
- `*_All_Customers_Full_Report.csv` bestand in export directory
- Geldige `config.json` voor HTML instellingen

## �🔧 Troubleshooting

### Veelvoorkomende Problemen

#### "Module niet gevonden"

```powershell
# Installeer Microsoft Graph modules handmatig
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.Governance -Scope CurrentUser
```

#### "Insufficient privileges"

- Controleer Azure AD App permissions
- Zorg voor admin consent op tenant niveau
- Verificeer client secret geldigheid

#### "Credentials file not found"

- Maak `credentials.json` in script directory
- Controleer JSON syntax en formatting
- Zorg voor juiste property names

#### "Group members not detected"

**Symptomen:**

- Script rapporteert groepsleden niet in de output
- Alleen directe rol-toewijzingen zijn zichtbaar
- Missing group membership data in reports

**Mogelijke oorzaken en oplossingen:**

1. **Microsoft Graph permissions**:

   ```text
   Benodigde permissions:
   - Group.Read.All (Application permission)
   - Directory.Read.All (Application permission)
   ```

2. **Admin consent**:

   - Zorg dat admin consent is verleend voor alle permissions
   - Check Azure AD > App registrations > [Your App] > API permissions
   - "Grant admin consent" moet groen zijn

3. **Groep configuratie**:

   - Verificeer dat security groups bestaan in de tenant
   - Check of groepen daadwerkelijk leden hebben
   - Controleer of groepen zijn toegewezen aan Azure AD rollen

4. **Script logging controleren**:

   ```powershell
   # Run script met verbose output
   .\Get-PIMUsers.ps1 -Verbose
   
   # Check voor specifieke error messages
   # Kijk naar "Group enumeration" sectie in output
   ```

5. **Manual verificatie**:

   ```powershell
   # Test Group API connectivity
   Connect-MgGraph -Scopes "Group.Read.All"
   Get-MgGroup -Filter "displayName eq 'YourGroupName'"
   Get-MgGroupMember -GroupId "group-id-here"
   ```

## 🤝 Contributing

1. **Fork** het repository
2. **Create** een feature branch (`git checkout -b feature/AmazingFeature`)
3. **Commit** je changes (`git commit -m 'Add AmazingFeature'`)
4. **Push** naar branch (`git push origin feature/AmazingFeature`)
5. **Open** een Pull Request

## 📝 Changelog

### v1.0 (2025-08-16)

- ✅ **Multi-tenant ondersteuning** met flexibele credentials
- ✅ **Groepsleden detectie** voor alle rol-toewijzingen
- ✅ **Modern HTML Dashboard** met dark/light mode
- ✅ **Nieuwe bestandsnaam conventie** zonder timestamps
- ✅ **Uitgebreide error handling** en logging
- ✅ **DataTables integratie** voor interactieve tabellen
- ✅ **Per-klant rapportage** met complete segregatie
- ✅ **Security metrics** en compliance tracking

## 📄 Licentie

Dit project is gelicenseerd onder de [MIT License](LICENSE).

## 👨‍💻 Auteur

### PowerShell Script voor PIM & Permanent Role Rapportage

- Versie: 1.0
- Laatste update: 2025-08-16

## 🙏 Dankbetuigingen

- **Microsoft Graph PowerShell SDK** team
- **DataTables** voor table functionaliteit  
- **FontAwesome** voor moderne iconen
- **jQuery** voor DOM manipulatie

---

💡 **Tip**: Voor de beste ervaring, open het HTML dashboard in een moderne browser zoals Chrome, Firefox, of Edge.

🔒 **Security**: Bewaar credential bestanden veilig en deel ze nooit in version control.

📊 **Analytics**: Gebruik de HTML dashboard voor real-time insights en de CSV bestanden voor uitgebreide analyse. Privileged-Uses-Report-MultiTenant
