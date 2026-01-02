#!/bin/bash
# Script pour incrémenter le numéro de build d'une application Xcode.

# Répertoire du fichier de configuration
CONFIG_FILE="$SRCROOT/$PRODUCT_NAME/Config.xcconfig"

# Vérifie si le fichier de configuration existe
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Le fichier de configuration $CONFIG_FILE n'existe pas."
  exit 1
fi

# Obtenir la date actuelle au format YYYYMMDD
current_date=$(date "+%Y%m%d")

# Format de la date YYYYMMDD
DATE_FORMAT=$(date +%Y%m%d)

# Lire le numéro de build actuel depuis le fichier Info.plist
CURRENT_BUILD_NUMBER=$(awk -F "=" '/BUILD_NUMBER/ {print $2}' Config.xcconfig | tr -d ' ')


# Extraire la partie numérique du numéro de build
CURRENT_DATE=$(echo "$CURRENT_BUILD_NUMBER" | cut -c1-8)
CURRENT_INCREMENT=$(echo "$CURRENT_BUILD_NUMBER" | cut -c9-10)

# Vérifier si la date actuelle est différente de la date du build actuel
if [ "$DATE_FORMAT" != "$CURRENT_DATE" ]; then
    # Si la date est différente, réinitialiser le numéro d'incrémentation à 01
    NEW_BUILD_NUMBER="${DATE_FORMAT}01"
else
    # Sinon, incrémenter le numéro d'incrémentation
    NEW_INCREMENT=$(printf "%02d" $((10#$CURRENT_INCREMENT + 1)))
    NEW_BUILD_NUMBER="${DATE_FORMAT}${NEW_INCREMENT}"
fi


# Mettre à jour le fichier de configuration avec le nouveau numéro de build
sed -i.bak -e "/BUILD_NUMBER =/ s/= .*/= $NEW_BUILD_NUMBER/" "$CONFIG_FILE"

# Supprimer le fichier de sauvegarde créé par sed
rm -f "$CONFIG_FILE.bak"

echo "Le numéro de build a été mis à jour à $new_build_number"
