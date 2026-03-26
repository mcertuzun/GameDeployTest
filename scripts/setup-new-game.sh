#!/bin/bash
set -e

# ─────────────────────────────────────────
# Kullanim: ./setup-new-game.sh <OyunAdi> <BundleID>
# Ornek:    ./setup-new-game.sh MatchBlast2 com.mcertuzun.matchblast2
# ─────────────────────────────────────────

GAME_NAME=$1
BUNDLE_ID=$2
TEMPLATE_REPO="mcertuzun/GameDeployTest"
GITHUB_USER="mcertuzun"
LINEAR_API_KEY="${LINEAR_API_KEY:-}"

# Renk kodlari
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
ask()   { echo -e "${YELLOW}[?]${NC} $1"; }

# ─── Kontroller ───
[ -z "$GAME_NAME" ] && error "Oyun adi gerekli! Kullanim: ./setup-new-game.sh <OyunAdi> <BundleID>"
[ -z "$BUNDLE_ID" ] && error "Bundle ID gerekli! Ornek: com.mcertuzun.matchblast2"
command -v gh >/dev/null || error "GitHub CLI (gh) kurulu degil"
command -v firebase >/dev/null || error "Firebase CLI kurulu degil. Kur: npm install -g firebase-tools"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Yeni Oyun Pipeline Kurulumu"
echo "  Oyun: $GAME_NAME"
echo "  Bundle ID: $BUNDLE_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── 1. GitHub Repo ───
log "GitHub repo olusturuluyor: $GITHUB_USER/$GAME_NAME"
gh repo create "$GAME_NAME" \
  --public \
  --description "Unity 6 mobile game — iOS & Android" \
  --clone
cd "$GAME_NAME"
echo "# $GAME_NAME" > README.md
git add . && git commit -m "init" && git push --set-upstream origin main
log "Repo hazir: https://github.com/$GITHUB_USER/$GAME_NAME"

# ─── 2. Template dosyalarini kopyala ───
log "Template dosyalari kopyalaniyor..."
TEMPLATE_DIR=$(mktemp -d)
git clone "https://github.com/$TEMPLATE_REPO.git" "$TEMPLATE_DIR" --depth=1

# Workflow
mkdir -p .github/workflows
cp "$TEMPLATE_DIR/.github/workflows/build.yml" .github/workflows/
cp "$TEMPLATE_DIR/.github/workflows/notify-linear.yml" .github/workflows/

# Fastlane
mkdir -p fastlane
cp "$TEMPLATE_DIR/fastlane/Fastfile" fastlane/
cp "$TEMPLATE_DIR/fastlane/Appfile" fastlane/
cp "$TEMPLATE_DIR/fastlane/Matchfile" fastlane/

# Build script
mkdir -p Assets/Editor Assets/Plugins/Android
cp "$TEMPLATE_DIR/Assets/Editor/BuildScript.cs" Assets/Editor/

# Gemfile
cp "$TEMPLATE_DIR/Gemfile" .
cp "$TEMPLATE_DIR/Gemfile.lock" .

# codemagic.yaml
cp "$TEMPLATE_DIR/codemagic.yaml" .

# gitignore
cp "$TEMPLATE_DIR/.gitignore" .

rm -rf "$TEMPLATE_DIR"
log "Template dosyalari kopyalandi"

# ─── 3. Bundle ID guncelle ───
log "Bundle ID guncelleniyor: $BUNDLE_ID"
sed -i '' "s/com.mcertuzun.game01/$BUNDLE_ID/g" fastlane/Appfile
sed -i '' "s/com.mcertuzun.game01/$BUNDLE_ID/g" fastlane/Matchfile
sed -i '' "s/com.mcertuzun.game01/$BUNDLE_ID/g" fastlane/Fastfile
sed -i '' "s/com.mcertuzun.game01/$BUNDLE_ID/g" codemagic.yaml
log "Bundle ID guncellendi"

# ─── 4. GitHub Secrets aktar ───
log "GitHub Secrets aktariliyor..."
SECRETS=(
  "ASC_KEY_ID"
  "ASC_ISSUER_ID"
  "ASC_KEY_CONTENT"
  "MATCH_PASSWORD"
  "FIREBASE_TOKEN"
  "LINEAR_API_KEY"
  "CODEMAGIC_API_TOKEN"
)
for SECRET in "${SECRETS[@]}"; do
  VALUE=$(gh secret list --repo "$TEMPLATE_REPO" 2>/dev/null | grep "$SECRET" | head -1)
  if [ -n "$VALUE" ]; then
    # Secret degerini template repodan al
    warn "$SECRET: Manuel olarak eklemen gerekiyor (guvenlik nedeniyle otomatik aktarilmiyor)"
  fi
done

# Secrets'i direkt ekle (mevcut degerlerden)
gh secret set ASC_KEY_ID --repo "$GITHUB_USER/$GAME_NAME" \
  --body "$(gh secret list --repo $TEMPLATE_REPO | grep ASC_KEY_ID)" 2>/dev/null || \
  warn "ASC_KEY_ID manuel eklenecek"

# Firebase yeni app icin
ask "Firebase App ID'yi girin (console.firebase.google.com'dan alin): "
read FIREBASE_APP_ID
gh secret set FIREBASE_APP_ID --repo "$GITHUB_USER/$GAME_NAME" --body "$FIREBASE_APP_ID"
log "FIREBASE_APP_ID eklendi"

ask "google-services.json dosyasinin tam yolunu girin: "
read GOOGLE_SERVICES_PATH
gh secret set GOOGLE_SERVICES_JSON --repo "$GITHUB_USER/$GAME_NAME" < "$GOOGLE_SERVICES_PATH"
log "GOOGLE_SERVICES_JSON eklendi"

# Diger secretlari template'den kopyala
for SECRET in "ASC_KEY_ID" "ASC_ISSUER_ID" "MATCH_PASSWORD" "FIREBASE_TOKEN" "LINEAR_API_KEY" "CODEMAGIC_API_TOKEN" "CODEMAGIC_APP_ID"; do
  warn "$SECRET icin deger girin (bos birakabilirsin, sonra eklersin):"
  read -s SECRET_VALUE
  if [ -n "$SECRET_VALUE" ]; then
    gh secret set "$SECRET" --repo "$GITHUB_USER/$GAME_NAME" --body "$SECRET_VALUE"
    log "$SECRET eklendi"
  fi
done

# ASC_KEY_CONTENT (p8 dosyasindan)
ask "p8 dosyasinin tam yolunu girin (~/.fastlane/keys/AuthKey_xxx.p8): "
read P8_PATH
if [ -f "$P8_PATH" ]; then
  gh secret set ASC_KEY_CONTENT --repo "$GITHUB_USER/$GAME_NAME" < "$P8_PATH"
  log "ASC_KEY_CONTENT eklendi"
fi

# ─── 5. Linear proje olustur ───
if [ -n "$LINEAR_API_KEY" ]; then
  log "Linear'da proje olusturuluyor..."

  # Proje olustur
  QUERY="{\"query\":\"mutation { projectCreate(input: { name: \\\"$GAME_NAME — Mobile\\\", description: \\\"Unity 6 mobile game\\\", color: \\\"#6366f1\\\" }) { project { id name } } }\"}"
  PROJECT_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$QUERY")
  log "Linear projesi olusturuldu: $GAME_NAME — Mobile"
else
  warn "LINEAR_API_KEY bulunamadi, Linear projesi manuel olusturulacak"
fi

# ─── 6. Dosyalari push et ───
log "Dosyalar push ediliyor..."
git add .
git commit -m "ci: add Unity 6 build pipeline from template"
git push
log "Pipeline push edildi"

# ─── 7. develop branch olustur ───
git checkout -b develop
git push --set-upstream origin develop
git checkout main
log "develop branch olusturuldu"

# ─── Ozet ───
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kurulum Tamamlandi!"
echo ""
echo "  Repo:     https://github.com/$GITHUB_USER/$GAME_NAME"
echo "  Actions:  https://github.com/$GITHUB_USER/$GAME_NAME/actions"
echo "  Bundle:   $BUNDLE_ID"
echo ""
echo "  Siradaki adimlar:"
echo "  1. Unity Hub'da yeni proje ac -> $GAME_NAME klasorune"
echo "  2. GitHub Actions -> Run workflow -> platform + runner sec"
echo "  3. Firebase Console'da testers grubuna ekip maillerini ekle"
echo "  4. TestFlight'ta internal testers'i davet et"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
