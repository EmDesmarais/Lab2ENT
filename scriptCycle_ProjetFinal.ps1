# ----------------------------------------------------------------------------- 
# Script : script1_projetFinal.ps1 
# Auteur : Émile Desmarais 
# Description : Script pour faire différents types de backup 
# Paramètres : 
# Date : 30 Avril 2025 
# ----------------------------------------------------------------------------- 

$csvPath = "./fairebackup.csv" 
$backupDossier = "C:\backups"

function full_backup($dossier, $backupDossier,$excludeList) {
    
    #Write-Host $backupDossier
	
#Récupérer le nom du dossier (MAIS pas TOUT le path)
    $nomDossier = Split-Path -Path $dossier -Leaf 

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
#Créer le nom pour le fichier ZIP selon le format
    $zipName = "${nomDossier}_${timestamp}_full.zip"
    #Write-Host $zipName
    $zipPath = Join-Path -Path $backupDossier -ChildPath $zipName #Pour que ce soit C:/backups/zipName (donc C:/backups/doc1_2024-03-19_20-30-15_full.zip) par exemple
    #Write-Host $zipPath

#Crée le dossier temp qui va contenir
    $dossierTemp = Join-Path $env:TEMP "copie_temp"

    if (Test-Path $dossierTemp) {   #Si le dossier existe déjà (et il va déjà exister si je fais la cmd plusieurs fois)
        Remove-Item -Path $dossierTemp -Recurse -Force  #On le supprime
    }

    New-Item -ItemType Directory -Path $dossierTemp | Out-Null #Et on le recrée (CAR SINON on peut pas le créer vu que le nom existe déjà et on a donc une erreur)

    #Seulement inclure les fichiers qui sont pas dans les exclusions
    $fichierInclure = Get-ChildItem -Path $dossier -Recurse -File | Where-Object {
        $ext = $_.Extension.TrimStart('.').ToLower()
        -not ($excludeList -contains $ext)
    }
    
    foreach ($fichier in $fichierInclure) {
        #Copier le fichier dans le dossier à ZIP
                        #On prend le NOM et on enlève le début (donc le C:/doc1 ou autre)
        $relativePath = $fichier.FullName.Substring($dossier.Length)
        #On fait ensuite son nouveau path qui le dossier temp 
        $destPath = Join-Path $dossierTemp $relativePath

        #on crée le répertoire du dossier SI celui-ci n'existe pas
        New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null #enleve message confirmation

        Copy-Item -Path $fichier.FullName -Destination $destPath -Force
    }

    #Compress le fichier (et tout les fichiers / sous-dossiers)
    Compress-Archive -Path "$dossierTemp\*" -DestinationPath $zipPath

    #Remove-Item -Path $dossierTemp -Recurse -Force
    
    #Message optionnel ?
    Write-Host "Backup complet cree : $zipPath"
}

function verifDossierExiste {
    param (
        [string]$backupDossier
    )
    
    # Crée le dossier de backup s'il n'existe pas 
    if (-not (Test-Path $backupDossier)) {
        New-Item -Path $backupDossier -ItemType Directory | Out-Null
    }
}

function differential_backup {
    param (
        [string]$dossier,
        [string]$backupDossier,
        [string]$excludeList,
        [int]$cycle
    )

    $nomDossier = Split-Path -Path $dossier -Leaf

    # Cherche les backups full existants
    $backupsFull = Get-ChildItem -Path $backupDossier -Filter "${nomDossier}_*_full.zip" | Sort-Object Name -Descending

    if ($backupsFull.Count -eq 0) {
        Write-Host "Aucun full backup fait pour '$nomDossier'. Un full backup sera cree."
        full_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList
        return
    }

    $dernierFull = $backupsFull[0]
    $dateStr = ($dernierFull.BaseName -split "_")[1] + "_" + ($dernierFull.BaseName -split "_")[2]
    $dateDernierFull = [datetime]::ParseExact($dateStr, "yyyy-MM-dd_HH-mm-ss", $null)

    # Compte les backups différentiels depuis le dernier full
    $diffDepuisFull = Get-ChildItem -Path $backupDossier -Filter "${nomDossier}_*_diff.zip" | Where-Object {
        $backupDateStr = ($_.BaseName -split "_")[1] + "_" + ($_.BaseName -split "_")[2]
        $backupDate = [datetime]::ParseExact($backupDateStr, "yyyy-MM-dd_HH-mm-ss", $null)
        $backupDate -gt $dateDernierFull
    }

    if ($diffDepuisFull.Count -ge $cycle) {
        Write-Host "Cycle de $cycle backups differentiels atteints pour '$nomDossier'. Creation d'un full backup et suppression des anciens differentiels."

        # Supprime les anciens différentiels
        foreach ($diff in $diffDepuisFull) {
            Remove-Item -Path $diff.FullName -Force
        }

        # Crée un nouveau full
        full_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList
        return
    }

    # Fichiers modifiés depuis le dernier full
    $fichiersModifies = Get-ChildItem -Path $dossier -Recurse -File | Where-Object {
        $ext = $_.Extension.TrimStart('.').ToLower()
        -not ($excludeList -contains $ext) -and ($_.LastWriteTime -gt $dateDernierFull)
    }

    if ($fichiersModifies.Count -eq 0) {
        Write-Host "Aucun fichier modifie depuis le dernier full backup. Aucun backup differentiel cree."
        return
    }    

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $zipName = "${nomDossier}_${timestamp}_diff.zip"
    $zipPath = Join-Path -Path $backupDossier -ChildPath $zipName

    $dossierTemp = Join-Path $env:TEMP "copie_temp"

    if (Test-Path $dossierTemp) {
        Remove-Item -Path $dossierTemp -Recurse -Force
    }

    New-Item -ItemType Directory -Path $dossierTemp | Out-Null

    foreach ($fichier in $fichiersModifies) {
        $relativePath = $fichier.FullName.Substring($dossier.Length)
        $destPath = Join-Path $dossierTemp $relativePath

        New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
        Copy-Item -Path $fichier.FullName -Destination $destPath -Force
    }

    Compress-Archive -Path "$dossierTemp\*" -DestinationPath $zipPath
    #Remove-Item -Path $dossierTemp -Recurse -Force

    Write-Host "Backup differentiel cree : $zipPath"
}



function incremental_backup {
    param (
        [string]$dossier,
        [string]$backupDossier,
        [string]$excludeList,
        [int]$cycle
    )

    $nomDossier = Split-Path -Path $dossier -Leaf

    # Cherche tous les backups full et incrémentaux existants
    $backupsExistants = Get-ChildItem -Path $backupDossier -Filter "${nomDossier}_*.zip" |
        Where-Object { $_.Name -match "_(full|incr)\.zip$" } | Sort-Object Name -Descending

    # S’il n’y a pas de backup précédent, faire un full backup
    if ($backupsExistants.Count -eq 0) {
        Write-Host "Aucun backup precedent pour '$nomDossier'. Un full backup sera cree."
        full_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList
        return
    }

    # Trouve le dernier full backup
    $dernierFull = Get-ChildItem -Path $backupDossier -Filter "${nomDossier}_*_full.zip" |
        Sort-Object Name -Descending | Select-Object -First 1

    if (-not $dernierFull) {
        Write-Host "Aucun full backup trouve pour '$nomDossier'. Un full backup sera cree."
        full_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList
        return
    }

    # Extrait la date du dernier full
    $dateStr = ($dernierFull.BaseName -split "_")[1] + "_" + ($dernierFull.BaseName -split "_")[2]
    $dateDernierFull = [datetime]::ParseExact($dateStr, "yyyy-MM-dd_HH-mm-ss", $null)

    # Compte le nombre de backups incrémentaux depuis le dernier full
    $incrDepuisFull = Get-ChildItem -Path $backupDossier -Filter "${nomDossier}_*_incr.zip" | Where-Object {
        $backupDateStr = ($_.BaseName -split "_")[1] + "_" + ($_.BaseName -split "_")[2]
        $backupDate = [datetime]::ParseExact($backupDateStr, "yyyy-MM-dd_HH-mm-ss", $null)
        $backupDate -gt $dateDernierFull
    }

    if ($incrDepuisFull.Count -ge $cycle) {
        Write-Host "Cycle de $cycle backups atteints pour '$nomDossier'. Création d'un full backup et suppression des anciens incrémentaux."
        
        foreach ($incr in $incrDepuisFull) {
            Remove-Item -Path $incr.FullName -Force
        }

        # Créer un nouveau full backup
        full_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList
        return
    }

    # Fichiers modifiés depuis le dernier backup (full ou incrémental)
    $dernierBackup = $backupsExistants[0]
    $dateStrLast = ($dernierBackup.BaseName -split "_")[1] + "_" + ($dernierBackup.BaseName -split "_")[2]
    $dateDernierBackup = [datetime]::ParseExact($dateStrLast, "yyyy-MM-dd_HH-mm-ss", $null)

    $fichiersModifies = Get-ChildItem -Path $dossier -Recurse -File | Where-Object {
        $ext = $_.Extension.TrimStart('.').ToLower()
        -not ($excludeList -contains $ext) -and ($_.LastWriteTime -gt $dateDernierBackup)
    }

    if ($fichiersModifies.Count -eq 0) {
        Write-Host "Aucun changement detecte dans '$nomDossier' depuis le dernier backup. Aucun backup incremental cree."
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $zipName = "${nomDossier}_${timestamp}_incr.zip"
    $zipPath = Join-Path -Path $backupDossier -ChildPath $zipName

    $dossierTemp = Join-Path $env:TEMP "copie_temp"

    if (Test-Path $dossierTemp) {
        Remove-Item -Path $dossierTemp -Recurse -Force
    }

    New-Item -ItemType Directory -Path $dossierTemp | Out-Null

    foreach ($fichier in $fichiersModifies) {
        $relativePath = $fichier.FullName.Substring($dossier.Length)
        $destPath = Join-Path $dossierTemp $relativePath

        New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
        Copy-Item -Path $fichier.FullName -Destination $destPath -Force
    }

    Compress-Archive -Path "$dossierTemp\*" -DestinationPath $zipPath
    #Remove-Item -Path $dossierTemp -Recurse -Force

    Write-Host "Backup incremental cree : $zipPath"
}

function lire_csv {

    $entries = Import-Csv -Path $csvPath
    $lineNumber = 1

    foreach ($entree in $entries) {
        $lineNumber++
        $dossier = $entree.Dossier
        $type = $entree.TypeBackup.ToLower()
        $exclusions = $entree.Exclusions
        $cycle = $entree.Cycle
    
        #SI dossier existe pas
        if (-not (Test-Path $dossier)) { 
            Write-Host "Erreur dans la ligne $lineNumber du fichier"
            Write-Host "Le dossier '$dossier' n'existe pas"
            Write-Host "Vous devez corriger le fichier avant de relancer ce script"
            return
        }
    
        #SI MODE existe pas
        if ($type -notin @("full", "incremental", "differential")) {
            Write-Host "Erreur dans la ligne $lineNumber du fichier"
            Write-Host "Le type de backup '$type' n'existe pas"
            Write-Host "Vous devez corriger le fichier avant de relancer ce script"
            return
        }
    
        #SI le cycle est pas bon (Doit etre chiffre entier positif)
        if ($type -in @("incremental", "differential")) {
            if (-not ($cycle -as [int]) -or ([int]$cycle -le 0)) {
                Write-Host "Erreur dans la ligne $lineNumber du fichier"
                Write-Host "Le cycle '$cycle' n'est pas un chiffre entier positif"
                Write-Host "Vous devez corriger le fichier avant de relancer ce script"
                return
            }
        }
        
    
        # liste d’exclusions
        $excludeList = @()
        if ($exclusions -ne "") {
            $excludeList = $exclusions -split "-"
        }
    
        # Appel fonction selon type backup (TOUS FULL pour l'instant)
        switch ($type) {
            "full" {
                full_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList
                
            }
            "incremental" {
                incremental_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList -cycle $cycle
                
            }
            "differential" {
                differential_backup -dossier $dossier -backupDossier $backupDossier -excludeList $excludeList -cycle $cycle

                
            }
        }
    }
}


verifDossierExiste($backupDossier)
lire_csv



