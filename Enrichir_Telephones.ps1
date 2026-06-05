# ==============================================================================
# ENRICHISSEMENT DES NUMÉROS DE TÉLÉPHONE POUR LES BOUTIQUES LUMIOS
# Ce script parcourt boutiques_geocoded.json et cherche les numéros de téléphone
# ==============================================================================

$jsonPath = Join-Path -Path $PSScriptRoot -ChildPath "boutiques_geocoded.json"

if (-not (Test-Path $jsonPath)) {
    Write-Error "Le fichier boutiques_geocoded.json est introuvable."
    exit
}

# Charger les boutiques
Write-Host "Chargement de la base de données des boutiques..." -ForegroundColor Cyan
$boutiques = Get-Content $jsonPath -Raw | ConvertFrom-Json
$total = $boutiques.Count
Write-Host "$total boutiques chargées." -ForegroundColor Green

# Demander une clé API Google Places (Recommandé pour éviter d'être bloqué)
Write-Host ""
Write-Host "--------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Pour chercher les téléphones sur Google Maps (Google Places),"
Write-Host "l'utilisation d'une clé API Google Cloud est fortement recommandée."
Write-Host "Si vous n'en avez pas, le script utilisera une recherche publique alternative (plus lente et sujette aux blocages)."
Write-Host "--------------------------------------------------------" -ForegroundColor Yellow
$apiKey = Read-Host "Entrez votre clé API Google Places (laissez vide pour utiliser la méthode publique)"
$apiKey = $apiKey.Trim()

$countUpdated = 0

for ($i = 0; $i -lt $total; $i++) {
    $b = $boutiques[$i]
    
    # Ne chercher que si le téléphone n'est pas déjà présent
    if (-not $b.telephone) {
        $nom = $b.nom
        $ville = $b.city
        $adresse = $b.adresse
        
        Write-Host "[$($i+1)/$total] Recherche pour : $nom ($ville)... " -NoNewline -ForegroundColor White
        
        $phoneFound = $null
        
        if ($apiKey) {
            # Utilisation de l'API Google Places (Text Search)
            $query = [uri]::EscapeDataString("$nom, $adresse, $ville, France")
            $url = "https://maps.googleapis.com/maps/api/place/textsearch/json?query=$query&key=$apiKey"
            
            try {
                $response = Invoke-RestMethod -Uri $url -Method Get
                if ($response.status -eq "OK" -and $response.results.Count -gt 0) {
                    $placeId = $response.results[0].place_id
                    
                    # Récupérer les détails avec le numéro de téléphone
                    $detailsUrl = "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=formatted_phone_number&key=$apiKey"
                    $detailsResponse = Invoke-RestMethod -Uri $detailsUrl -Method Get
                    if ($detailsResponse.status -eq "OK" -and $detailsResponse.result.formatted_phone_number) {
                        $phoneFound = $detailsResponse.result.formatted_phone_number
                    }
                }
            } catch {
                Write-Host "Erreur API Google" -ForegroundColor Red
            }
        } else {
            # Méthode alternative publique (Scraping léger de DuckDuckGo)
            $query = [uri]::EscapeDataString("telephone '$nom' '$ville' $adresse")
            $searchUrl = "https://html.duckduckgo.com/html/?q=$query"
            
            try {
                $web = Invoke-WebRequest -Uri $searchUrl -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -TimeoutSec 5
                if ($web.Content -match '(\+33|0)[1-9](\s*\d{2}){4}') {
                    $phoneFound = $Matches[0]
                }
            } catch {
                # Silencieux
            }
            
            # Attendre 2 secondes entre les requêtes pour éviter le bannissement d'IP
            Start-Sleep -Seconds 2
        }
        
        if ($phoneFound) {
            $b | Add-Member -MemberType NoteProperty -Name "telephone" -Value $phoneFound -Force
            $countUpdated++
            Write-Host "Trouvé : $phoneFound" -ForegroundColor Green
        } else {
            Write-Host "Non trouvé" -ForegroundColor Gray
        }
        
        # Sauvegarde régulière toutes les 10 modifications
        if ($countUpdated -gt 0 -and $countUpdated % 10 -eq 0) {
            $boutiques | ConvertTo-Json -Depth 100 | Out-File $jsonPath -Encoding utf8
        }
    }
}

# Sauvegarde finale
$boutiques | ConvertTo-Json -Depth 100 | Out-File $jsonPath -Encoding utf8
Write-Host ""
Write-Host "Terminé ! $countUpdated boutiques ont été enrichies avec un numéro de téléphone." -ForegroundColor Green
Write-Host "Le fichier $jsonPath a été mis à jour." -ForegroundColor Green
