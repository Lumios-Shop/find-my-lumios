# ==============================================================================
# ENRICHISSEMENT DES NUMÉROS DE TÉLÉPHONE POUR LES BOUTIQUES LUMIOS
# Version DuckDuckGo Lite (détection de blocage et validation des numéros)
# ==============================================================================

$jsonPath = Join-Path -Path $PSScriptRoot -ChildPath "boutiques_geocoded.json"

if (-not (Test-Path $jsonPath)) {
    Write-Error "Le fichier boutiques_geocoded.json est introuvable."
    exit
}

# Charger les boutiques en UTF-8
Write-Host "Chargement de la base de données..." -ForegroundColor Cyan
$jsonText = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
if ($jsonText -match '[\u00C2-\u00C3][\u0080-\u00BF]') {
    Write-Host "Détection et réparation des caractères accentués corrompus dans la base de données..." -ForegroundColor Yellow
    $win1252 = [System.Text.Encoding]::GetEncoding(1252)
    $utf8 = [System.Text.Encoding]::UTF8
    $bytes = $win1252.GetBytes($jsonText)
    $jsonText = $utf8.GetString($bytes)
}
$boutiques = $jsonText | ConvertFrom-Json
$total = $boutiques.Count
Write-Host "$total boutiques chargées." -ForegroundColor Green

$userAgents = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Edge/120.0.0.0"
)

# Liste de faux numéros générés par les tokens de challenge DDG
$falsePositives = @("06 23 58 33 84", "02 63 94 12 76")

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$countUpdated = 0

for ($i = 0; $i -lt $total; $i++) {
    $b = $boutiques[$i]
    
    # Ignorer si le téléphone est déjà présent
    if ($b.telephone) {
        continue
    }

    $nom = $b.nom
    $ville = $b.city
    $adresse = $b.adresse

    # Nettoyer les caractères spéciaux et préparer la recherche
    $cleanNom = $nom -replace '[\x00-\x1F\x7F]', ''
    $queryStr = "telephone '$cleanNom' '$ville' $adresse"
    
    Write-Host "[$($i+1)/$total] Recherche pour : $nom ($ville)... " -NoNewline -ForegroundColor White
    
    $phoneFound = $null
    $userAgent = $userAgents[(Get-Random -Maximum $userAgents.Count)]
    
    try {
        $body = @{ q = $queryStr }
        # Utilisation de DDG Lite avec Basic Parsing
        $web = Invoke-WebRequest -Uri "https://lite.duckduckgo.com/lite/" -Method Post -Body $body -UserAgent $userAgent -UseBasicParsing -TimeoutSec 10
        
        # Détecter le blocage bot / challenge DuckDuckGo
        if ($web.Content -match 'anomaly\.js' -or $web.Content -match 'challenge-form' -or $web.Content -match 'botnet' -or $web.Content -match 'vqd=') {
            # Si le jeton vqd contient des chiffres qui font de faux positifs
            # On vérifie si la page est saine en regardant s'il y a des résultats de recherche
            if ($web.Content -notmatch 'class=''result-link''') {
                Write-Host "Bloqué par DuckDuckGo (Détection Bot). Pause de 15 secondes..." -ForegroundColor Yellow
                Start-Sleep -Seconds 15
                continue
            }
        }

        # Supprimer les inputs et forms
        $cleanHtml = $web.Content -replace '<input[^>]*>', '' -replace '<form[^>]*>', ''
        
        # Matcher les formats de numéros de téléphone français
        if ($cleanHtml -match '(?:\+33|0)\s*[1-9](?:\s*\d{2}){4}') {
            $rawPhone = $Matches[0]
            # Normaliser
            $cleanPhone = $rawPhone -replace '[^\d+]', ''
            if ($cleanPhone.StartsWith("+33")) {
                $cleanPhone = "0" + $cleanPhone.Substring(3)
            }
            if ($cleanPhone.Length -eq 10) {
                $formatted = "{0} {1} {2} {3} {4}" -f $cleanPhone.Substring(0,2), $cleanPhone.Substring(2,2), $cleanPhone.Substring(4,2), $cleanPhone.Substring(6,2), $cleanPhone.Substring(8,2)
                
                # S'assurer que le numéro trouvé n'est pas un faux positif de token DDG
                if ($falsePositives -notcontains $formatted) {
                    $phoneFound = $formatted
                }
            }
        }
    } catch {
        Write-Host "Erreur connection/timeout. Pause de 5 secondes... " -ForegroundColor Red
        Start-Sleep -Seconds 5
        continue
    }
    
    if ($phoneFound) {
        $b | Add-Member -MemberType NoteProperty -Name "telephone" -Value $phoneFound -Force
        $countUpdated++
        Write-Host "Trouvé : $phoneFound" -ForegroundColor Green
        
        # Sauvegarde régulière en UTF-8 sans BOM à chaque succès
        $jsonText = $boutiques | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($jsonPath, $jsonText, $utf8NoBom)
    } else {
        Write-Host "Non trouvé" -ForegroundColor Gray
    }
    
    # Délai de sécurité plus large entre 3 et 5.5 secondes
    $delay = Get-Random -Minimum 3000 -Maximum 5500
    Start-Sleep -Milliseconds $delay
}

# Sauvegarde finale
$jsonText = $boutiques | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($jsonPath, $jsonText, $utf8NoBom)
Write-Host ""
Write-Host "Terminé ! $countUpdated nouvelles boutiques enrichies avec succès." -ForegroundColor Green
