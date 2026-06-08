# ==============================================================================
# SCRIPT DE MISE À JOUR ET DE FUSION DES BOUTIQUES LUMIOS
# ==============================================================================

param (
    [string]$ExcelName = "Boutiques_062026.xlsx",
    [string]$JsonName = "boutiques_geocoded.json",
    [bool]$AutoPush = $true
)

$PSScriptRoot = Get-Location
$ExcelPath = Join-Path $PSScriptRoot $ExcelName
$JsonPath = Join-Path $PSScriptRoot $JsonName
$TempExcelPath = Join-Path $PSScriptRoot "Boutiques_temp_run.xlsx"
$ExtractPath = Join-Path $PSScriptRoot "excel_temp_run"

# Encodage UTF-8 sans BOM pour les fichiers JSON
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host "=== Lancement de la mise à jour de la base des boutiques ===" -ForegroundColor Cyan
Write-Host "Fichier Excel source : $ExcelName" -ForegroundColor White
Write-Host "Base de données cible : $JsonName" -ForegroundColor White

if (-not (Test-Path $ExcelPath)) {
    Write-Error "Fichier Excel introuvable : $ExcelPath"
    exit 1
}

# 1. CHARGEMENT DES DONNÉES EXISTANTES
$existingStores = @()
if (Test-Path $JsonPath) {
    Write-Host "Chargement de la base existante..." -ForegroundColor White
    $jsonText = [System.IO.File]::ReadAllText($JsonPath, [System.Text.Encoding]::UTF8)
    $existingStores = $jsonText | ConvertFrom-Json
    Write-Host "$($existingStores.Count) boutiques existantes chargées." -ForegroundColor Green
} else {
    Write-Host "Aucune base existante trouvée. Une nouvelle base sera créée." -ForegroundColor Yellow
}

# Fonction de normalisation pour le matching robuste
function Get-NormalizationKey {
    param([string]$name, [string]$address)
    $n = ($name -replace '[^a-zA-Z0-9]', '').ToLower()
    $a = ($address -replace '[^a-zA-Z0-9]', '').ToLower()
    # Remplacement bis/ter pour tolérer les variations d'écriture
    $a = $a -replace 'bis', 'b' -replace 'ter', 't'
    return "$n`_$a"
}

function Get-FallbackKey {
    param([string]$name, [string]$postcode)
    $n = ($name -replace '[^a-zA-Z0-9]', '').ToLower()
    $p = ($postcode -replace '[^a-zA-Z0-9]', '').ToLower()
    return "$n`_$p"
}

# Dictionnaires de matching
$primaryDict = @{}
$fallbackDict = @{}
$fallbackCount = @{}
$demoStores = @()

foreach ($store in $existingStores) {
    if ($store.id -like "demo-*") {
        $demoStores += $store
        continue
    }
    
    $pKey = Get-NormalizationKey -name $store.nom -address $store.adresse
    if ($pKey) {
        $primaryDict[$pKey] = $store
    }
    
    $fKey = Get-FallbackKey -name $store.nom -postcode $store.postcode
    if ($fKey) {
        if (-not $fallbackDict.ContainsKey($fKey)) {
            $fallbackDict[$fKey] = $store
            $fallbackCount[$fKey] = 1
        } else {
            $fallbackCount[$fKey]++
        }
    }
}

# 2. PARSING DE L'EXCEL
Write-Host "Lecture du fichier Excel..." -ForegroundColor White

if (Test-Path $ExtractPath) {
    Remove-Item $ExtractPath -Recurse -Force | Out-Null
}
New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

if (Test-Path $TempExcelPath) {
    Remove-Item $TempExcelPath -Force | Out-Null
}

# Copie pour éviter le lock Excel
Copy-Item $ExcelPath -Destination $TempExcelPath -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($TempExcelPath, $ExtractPath)

$sharedStringsPath = Join-Path $ExtractPath "xl\sharedStrings.xml"
$sheetPath = Join-Path $ExtractPath "xl\worksheets\sheet1.xml"

# Parse les Shared Strings
$sharedStrings = @()
if (Test-Path $sharedStringsPath) {
    [xml]$ssXml = Get-Content -Path $sharedStringsPath -Encoding UTF8 -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($ssXml.NameTable)
    $ns.AddNamespace("ns", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
    
    $siNodes = $ssXml.SelectNodes("//ns:si", $ns)
    foreach ($si in $siNodes) {
        $text = ""
        $tNodes = $si.SelectNodes(".//ns:t", $ns)
        foreach ($t in $tNodes) {
            $text += $t.InnerText
        }
        $sharedStrings += $text
    }
}

# Parse la feuille XML
[xml]$sheetXml = Get-Content -Path $sheetPath -Encoding UTF8 -Raw
$nsSheet = New-Object System.Xml.XmlNamespaceManager($sheetXml.NameTable)
$nsSheet.AddNamespace("ns", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

$rowNodes = $sheetXml.SelectNodes("//ns:row", $nsSheet)
$excelStores = @()

foreach ($row in $rowNodes) {
    $rowNum = $row.GetAttribute("r")
    if ($rowNum -eq "1") { continue } # Sauter la ligne d'en-tête
    
    $cNodes = $row.SelectNodes("./ns:c", $nsSheet)
    $rowObj = @{
        A = ""
        B = ""
        C = ""
        D = ""
        E = ""
    }
    $hasData = $false
    
    foreach ($c in $cNodes) {
        $cellRef = $c.GetAttribute("r")
        $col = $cellRef -replace '\d+', ''
        
        $val = ""
        $vNode = $c.SelectSingleNode("./ns:v", $nsSheet)
        if ($vNode) {
            $rawVal = $vNode.InnerText
            $tAttr = $c.GetAttribute("t")
            if ($tAttr -eq "s") {
                $idx = [int]$rawVal
                if ($idx -ge 0 -and $idx -lt $sharedStrings.Count) {
                    $val = $sharedStrings[$idx]
                }
            } else {
                $val = $rawVal
            }
        }
        
        if ($val -ne $null -and $val.ToString().Trim() -ne "") {
            $hasData = $true
            $rowObj[$col] = $val.ToString().Trim()
        }
    }
    
    if ($hasData -and $rowObj.A -ne "") {
        $excelStores += $rowObj
    }
}

# Nettoyage fichiers temporaires Excel
Remove-Item $ExtractPath -Recurse -Force | Out-Null
Remove-Item $TempExcelPath -Force | Out-Null

Write-Host "$($excelStores.Count) boutiques lues depuis l'Excel." -ForegroundColor Green

# 3. FUSION ET CORRESPONDANCES
$mergedStores = @()
$storesToGeocode = @()
$matchedCount = 0

foreach ($excelStore in $excelStores) {
    $nom = $excelStore.A
    $adresse = $excelStore.B
    $postcode = $excelStore.C
    $city = $excelStore.D
    
    $pKey = Get-NormalizationKey -name $nom -address $adresse
    $fKey = Get-FallbackKey -name $nom -postcode $postcode
    
    $matchedStore = $null
    
    # 1. Recherche par Clé Primaire (Nom + Adresse)
    if ($primaryDict.ContainsKey($pKey)) {
        $matchedStore = $primaryDict[$pKey]
    }
    # 2. Recherche par Clé de Secours (Nom + Code Postal si unique)
    elseif ($fallbackDict.ContainsKey($fKey) -and $fallbackCount[$fKey] -eq 1) {
        $matchedStore = $fallbackDict[$fKey]
        Write-Host "Match de secours pour : $nom ($postcode) -> Adresse mise à jour : '$adresse' (ancien : '$($matchedStore.adresse)')" -ForegroundColor Yellow
    }
    
    if ($matchedStore) {
        # Conserver les données existantes en mettant à jour le nom/adresse selon l'Excel si besoin
        $newStore = @{
            id = $matchedStore.id
            nom = $nom
            adresse = $adresse
            postcode = $postcode
            city = $city
            lat = $matchedStore.lat
            lon = $matchedStore.lon
            score = $matchedStore.score
            label = $matchedStore.label
            telephone = $matchedStore.telephone
        }
        $mergedStores += $newStore
        $matchedCount++
    } else {
        # Marquer pour géocodage
        $newStore = @{
            id = $null # Sera assigné plus tard
            nom = $nom
            adresse = $adresse
            postcode = $postcode
            city = $city
            lat = $null
            lon = $null
            score = 0.0
            label = ""
            telephone = $null
        }
        $storesToGeocode += $newStore
    }
}

Write-Host "$matchedCount boutiques existantes conservées avec leurs données GPS/téléphones." -ForegroundColor Green
Write-Host "$($storesToGeocode.Count) nouvelles boutiques détectées à géocoder." -ForegroundColor Yellow

# 4. GÉOCODAGE DES NOUVELLES BOUTIQUES
if ($storesToGeocode.Count -gt 0) {
    Write-Host "Lancement du géocodage..." -ForegroundColor White
    $csvTempPath = Join-Path $PSScriptRoot "temp_to_geocode.csv"
    $csvResultPath = Join-Path $PSScriptRoot "temp_geocoded.csv"
    
    $csvHeader = "id,nom,adresse,postcode,city"
    $csvLines = @($csvHeader)
    
    for ($i = 0; $i -lt $storesToGeocode.Count; $i++) {
        $st = $storesToGeocode[$i]
        # Échappement des guillemets
        $id = $i
        $nomEscaped = $st.nom -replace '"', '""'
        $addrEscaped = $st.adresse -replace '"', '""'
        $pcEscaped = $st.postcode -replace '"', '""'
        $cityEscaped = $st.city -replace '"', '""'
        $csvLines += """$id"",""$nomEscaped"",""$addrEscaped"",""$pcEscaped"",""$cityEscaped"""
    }
    
    [System.IO.File]::WriteAllLines($csvTempPath, $csvLines, [System.Text.Encoding]::UTF8)
    
    # Appel API adresse.data.gouv.fr par curl
    Write-Host "Appel à l'API de géocodage nationale (lot)..." -ForegroundColor White
    & curl.exe -X POST -F "data=@$csvTempPath" -F "columns=adresse" -F "columns=postcode" -F "columns=city" -o $csvResultPath https://api-adresse.data.gouv.fr/search/csv/
    
    if (Test-Path $csvResultPath) {
        $geocodedResults = Import-Csv -Path $csvResultPath
        Write-Host "Résultats reçus de l'API de géocodage." -ForegroundColor Green
        
        foreach ($res in $geocodedResults) {
            $idx = [int]$res.id
            $st = $storesToGeocode[$idx]
            
            if ($res.latitude -and $res.longitude) {
                $st.lat = [double]$res.latitude
                $st.lon = [double]$res.longitude
                $st.score = if ($res.result_score) { [double]$res.result_score } else { 0.0 }
                $st.label = $res.result_label
                Write-Host "  [OK] $($st.nom) -> $($st.lat), $($st.lon) (score: $($st.score))" -ForegroundColor Gray
            } else {
                Write-Host "  [ÉCHEC] Impossible de géolocaliser : $($st.nom) - $($st.adresse) $($st.postcode) $($st.city)" -ForegroundColor Red
            }
            $mergedStores += $st
        }
        
        # Nettoyage
        Remove-Item $csvTempPath -Force | Out-Null
        Remove-Item $csvResultPath -Force | Out-Null
    } else {
        Write-Error "Échec de la récupération des coordonnées depuis l'API de géocodage !"
        # On ajoute quand même les non géocodés pour ne pas perdre la liste
        $mergedStores += $storesToGeocode
    }
}

# 5. ASSIGNATION DES IDS SÉQUENTIELS ET FUSION FINALE
$finalStoresList = @()

# Ajouter d'abord les boutiques de démonstration
foreach ($demo in $demoStores) {
    $finalStoresList += $demo
}

# Ajouter les boutiques réelles avec de nouveaux identifiants séquentiels
$nextId = 2
foreach ($store in $mergedStores) {
    $store.id = $nextId.ToString()
    $finalStoresList += $store
    $nextId++
}

# 6. ENREGISTREMENT
$jsonOutput = $finalStoresList | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($JsonPath, $jsonOutput, $utf8NoBom)
Write-Host ""
Write-Host "Base de données sauvegardée dans $JsonName ($($finalStoresList.Count) boutiques au total)." -ForegroundColor Green

# 7. ENRICHISSEMENT DES TÉLÉPHONES DES NOUVELLES BOUTIQUES
# Identifier combien de nouvelles boutiques n'ont pas de téléphone
$missingPhones = $finalStoresList | Where-Object { -not $_.telephone -and $_.id -notlike "demo-*" }
if ($missingPhones.Count -gt 0) {
    Write-Host ""
    Write-Host "Il y a $($missingPhones.Count) boutiques sans numéro de téléphone." -ForegroundColor Yellow
    Write-Host "Lancement automatique du script de recherche de téléphones (Enrichir_Telephones.ps1)..." -ForegroundColor White
    
    # Exécution du script existant
    & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Enrichir_Telephones.ps1")
}

# 8. GIT AUTO PUSH (SI DEMANDÉ)
if ($AutoPush) {
    Write-Host ""
    Write-Host "=== Déploiement automatique sur GitHub ===" -ForegroundColor Cyan
    & git add boutiques_geocoded.json
    & git commit -m "Mise a jour de la liste des boutiques via excel Boutiques_062026.xlsx"
    & git push
    Write-Host "Changements poussés avec succès ! Déploiement Netlify en cours..." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Mise à jour des boutiques terminée avec succès ! ===" -ForegroundColor Green
