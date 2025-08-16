# PIM & Permanent Role Users Report - Multi Tenant

Een uitgebreide PowerShell-oplossing voor het analyseren van Privileged Identity Management (PIM) en permanente roltoewijzingen in meerdere Microsoft 365/Azure AD tenants.

## 📋 Overzicht

Dit script biedt gedetailleerde rapportage over:

- **PIM rol-toewijzingen** (Eligible en Active)
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
- `20250816_PIM_Role_Dashboard.html` - **Interactief HTML Dashboard**

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

## 🔧 Troubleshooting

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

- Controleer `Group.Read.All` permission
- Verificeer groep bestaat in tenant
- Check output logs voor error details

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
