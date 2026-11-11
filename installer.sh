#!/usr/bin/env bash
# Installation d'un serveur Build with Fèmi : sécurité, Docker et panneau Dokploy.
#
# Testé sur Ubuntu 24.04 (mvps.net, novembre 2026). À lancer en root, sur un serveur neuf :
#
#   curl -fsSL https://raw.githubusercontent.com/build-with-femi/serveur/main/installer.sh -o installer.sh
#   bash installer.sh                 # installe tout, s'arrête aux confirmations humaines
#   bash installer.sh finaliser DOMAINE   # ferme le port 3000 une fois le panneau en HTTPS
#   bash installer.sh verifier        # contrôle l'état du serveur à tout moment
#
# Le script peut être relancé sans risque : chaque étape faite est notée et sautée ensuite.
# Journal : /var/log/bwf-installation.log (droits 600).

set -Eeuo pipefail

VERSION="2026-11-11"
ETAT_DIR=/var/lib/bwf
ETAT="$ETAT_DIR/etapes"
JOURNAL=/var/log/bwf-installation.log
SAUVEGARDE=/root/bwf-backup
MEMOIRE_MIN_MO="${BWF_MEMOIRE_MIN_MO:-3500}"   # 4 Go demandés ; le serveur de test met 1800
DISQUE_MIN_GO="${BWF_DISQUE_MIN_GO:-30}"
export DEBIAN_FRONTEND=noninteractive

# ---------- affichage et journal ----------

if [ -t 1 ]; then GRAS=$'\e[1m'; ORANGE=$'\e[38;5;202m'; VERT=$'\e[32m'; ROUGE=$'\e[31m'; FIN=$'\e[0m'
else GRAS=""; ORANGE=""; VERT=""; ROUGE=""; FIN=""; fi

journal() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$JOURNAL"; }
titre()   { printf '\n%s> %s%s\n' "$ORANGE$GRAS" "$*" "$FIN"; journal "== $*"; }
info()    { printf '  %s\n' "$*"; journal "$*"; }
ok()      { printf '  %sOK%s %s\n' "$VERT" "$FIN" "$*"; journal "OK $*"; }
arret()   { printf '\n  %sArrêt :%s %s\n\n' "$ROUGE$GRAS" "$FIN" "$*" >&2; journal "ARRET $*"; exit 1; }

# Les questions passent par le terminal, même quand le script arrive par un tuyau.
demander() {
  local question="$1" reponse
  printf '\n  %s%s%s ' "$GRAS" "$question" "$FIN" > /dev/tty
  read -r reponse < /dev/tty || reponse=""
  journal "QUESTION $question -> $reponse"
  printf '%s' "$reponse"
}
confirmer() { [ "$(demander "$1 Tape OUI pour continuer :")" = "OUI" ]; }

fait()  { grep -qx "$1" "$ETAT" 2>/dev/null; }
noter() { grep -qx "$1" "$ETAT" 2>/dev/null || echo "$1" >> "$ETAT"; }

trap 'journal "ERREUR ligne $LINENO : $BASH_COMMAND"; printf "\n  %sErreur ligne %s.%s Le détail est dans %s. Corrige puis relance : les étapes faites seront sautées.\n\n" "$ROUGE" "$LINENO" "$FIN" "$JOURNAL" >&2' ERR

ip_publique() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  # Derrière un NAT, l'adresse locale est privée : on demande l'adresse publique.
  if [[ -z "$ip" || "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
    ip=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "$ip")
  fi
  printf '%s' "$ip"
}

# ---------- étapes ----------

prerequis() {
  titre "Vérifications de départ"
  [ "$(id -u)" -eq 0 ] || arret "lance le script en root."
  mkdir -p "$ETAT_DIR" "$SAUVEGARDE"; chmod 700 "$ETAT_DIR" "$SAUVEGARDE"
  [ -f "$JOURNAL" ] || install -m 600 /dev/null "$JOURNAL"
  journal "installer.sh $VERSION"
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ] || arret "ce script est prévu pour Ubuntu 24.04 (trouvé : ${PRETTY_NAME:-inconnu})."
  [ "${VERSION_ID:-}" = "24.04" ] || info "Version testée : Ubuntu 24.04. Trouvée : $PRETTY_NAME. On continue, avec prudence."
  ok "$PRETTY_NAME, noyau $(uname -r), $(nproc) processeur(s)"

  local memoire_mo disque_go
  memoire_mo=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  disque_go=$(df -BG --output=size / | tail -1 | tr -dc '0-9')
  info "Mémoire : ${memoire_mo} Mo. Disque : ${disque_go} Go."
  [ "$memoire_mo" -ge "$MEMOIRE_MIN_MO" ] || arret "il faut au moins 4 Go de mémoire (trouvé ${memoire_mo} Mo). Prends l'offre au-dessus chez ton hébergeur."
  [ "$disque_go" -ge "$DISQUE_MIN_GO" ] || info "Disque sous ${DISQUE_MIN_GO} Go : il faudra nettoyer les images Docker régulièrement."

  if ! fait dokploy; then
    local occupes
    occupes=$(ss -tlnH '( sport = :80 or sport = :443 or sport = :3000 )' | wc -l)
    [ "$occupes" -eq 0 ] || arret "un programme écoute déjà sur 80, 443 ou 3000. Ce script attend un serveur neuf."
    ok "Ports 80, 443 et 3000 libres"
  fi
  [ -s /root/.ssh/authorized_keys ] || arret "aucune clé SSH dans /root/.ssh/authorized_keys. Envoie d'abord ta clé depuis ton ordinateur (voir le guide), puis relance."
}

systeme() {
  fait systeme && { ok "Système déjà à jour"; return; }
  titre "Mise à jour du système"
  apt-get update -q >> "$JOURNAL" 2>&1
  apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade >> "$JOURNAL" 2>&1
  apt-get -y -q autoremove >> "$JOURNAL" 2>&1
  apt-get -y -q install unattended-upgrades curl ca-certificates >> "$JOURNAL" 2>&1
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOT
  cat > /etc/apt/apt.conf.d/52-bwf-unattended <<'EOT'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOT
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >> "$JOURNAL" 2>&1
  ok "Système à jour, mises à jour de sécurité automatiques (sans redémarrage automatique)"

  local nom
  nom=$(demander "Nom de ce serveur (lettres, chiffres, tirets ; Entrée pour « bwf-serveur ») :")
  nom=${nom:-bwf-serveur}
  [[ "$nom" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || arret "nom invalide : « $nom »."
  hostnamectl set-hostname "$nom"
  if grep -qE '^127\.0\.1\.1\s' /etc/hosts; then sed -i -E "s/^127\.0\.1\.1\s.*/127.0.1.1\t$nom/" /etc/hosts
  else printf '127.0.1.1\t%s\n' "$nom" >> /etc/hosts; fi
  [ -d /etc/cloud/cloud.cfg.d ] && printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-bwf-hostname.cfg
  ok "Nom du serveur : $nom"
  noter systeme
}

redemarrage() {
  [ -f /var/run/reboot-required ] || return 0
  titre "Redémarrage nécessaire"
  info "Un nouveau noyau est installé. Redémarre maintenant, avant Docker."
  info "Après le redémarrage, reconnecte-toi et relance : bash installer.sh"
  if confirmer "Redémarrer maintenant ? Ta session va se couper une minute."; then
    journal "Redémarrage demandé"
    sync; reboot; exit 0
  fi
  arret "redémarre quand tu veux avec la commande reboot, puis relance le script."
}

memoire_echange() {
  fait echange && { ok "Mémoire d'échange déjà réglée"; return; }
  titre "Mémoire d'échange"
  local total_mo
  total_mo=$(swapon --show=SIZE --bytes --noheadings 2>/dev/null | awk '{s+=$1} END {print int(s/1048576)}')
  if [ "${total_mo:-0}" -ge 1900 ]; then
    ok "Mémoire d'échange existante gardée (${total_mo} Mo)"
  else
    [ -f /swapfile ] && arret "/swapfile existe déjà mais n'est pas actif. Vérifie-le à la main."
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >> "$JOURNAL" && swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Fichier d'échange /swapfile de 2 Go créé"
  fi
  printf 'vm.swappiness = 10\n' > /etc/sysctl.d/99-bwf.conf
  sysctl --system >> "$JOURNAL" 2>&1
  [ "$(sysctl -n vm.swappiness)" = "10" ] || arret "swappiness n'a pas pris la valeur 10."
  ok "swappiness = 10"
  noter echange
}

ssh_par_cle() {
  fait ssh && { ok "SSH déjà en clé uniquement"; return; }
  titre "Connexion SSH par clé uniquement"
  chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys
  info "Clés autorisées sur ce serveur :"
  ssh-keygen -lf /root/.ssh/authorized_keys | sed 's/^/    /'
  info "Compare ces empreintes avec la tienne, sur ton ordinateur : ssh-keygen -lf ~/.ssh/id_ed25519.pub"
  confirmer "Toutes ces clés sont à toi ?" || arret "retire les clés inconnues de /root/.ssh/authorized_keys, puis relance."

  local horodatage; horodatage=$(date -u +%Y%m%d-%H%M%S)
  mkdir -p "$SAUVEGARDE/ssh-$horodatage"
  cp -a /etc/ssh/sshd_config.d/. "$SAUVEGARDE/ssh-$horodatage/" 2>/dev/null || true
  # Ubuntu peut réactiver le mot de passe ici, et ce fichier est lu avant le nôtre.
  [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ] && echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/50-cloud-init.conf
  cat > /etc/ssh/sshd_config.d/99-bwf.conf <<'EOT'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
EOT
  chmod 600 /etc/ssh/sshd_config.d/99-bwf.conf
  [ -d /etc/cloud/cloud.cfg.d ] && printf 'ssh_pwauth: false\n' > /etc/cloud/cloud.cfg.d/99-bwf-ssh.cfg
  sshd -t || arret "configuration SSH invalide ; rien n'a été rechargé."
  systemctl reload ssh

  local applique
  applique=$(sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication) ' | awk '{print $2}' | sort -u)
  [ "$applique" = "no" ] || { restaurer_ssh "$horodatage"; arret "le mot de passe reste actif ; configuration annulée."; }

  info "Garde CETTE session ouverte. Ouvre un autre terminal sur ton ordinateur et lance :"
  info "    ssh root@$(ip_publique)"
  info "Puis, dans ce même autre terminal, vérifie que le mot de passe est refusé :"
  info "    ssh -o PubkeyAuthentication=no root@$(ip_publique)     (doit répondre Permission denied)"
  if ! confirmer "La connexion par clé marche ET le mot de passe est refusé ?"; then
    restaurer_ssh "$horodatage"
    arret "configuration SSH annulée, tout est comme avant. Vérifie ta clé puis relance."
  fi
  ok "SSH : clé uniquement, 3 essais au maximum"
  noter ssh
}

restaurer_ssh() {
  rm -f /etc/ssh/sshd_config.d/99-bwf.conf /etc/cloud/cloud.cfg.d/99-bwf-ssh.cfg
  cp -a "$SAUVEGARDE/ssh-$1/." /etc/ssh/sshd_config.d/ 2>/dev/null || true
  sshd -t && systemctl reload ssh
  journal "SSH restauré depuis $SAUVEGARDE/ssh-$1"
}

pare_feu() {
  fait parefeu && { ok "Pare-feu déjà actif"; return; }
  titre "Pare-feu et protection contre les essais de mot de passe"
  apt-get -y -q install ufw fail2ban python3-systemd >> "$JOURNAL" 2>&1
  ufw default deny incoming >> "$JOURNAL"
  ufw default allow outgoing >> "$JOURNAL"
  ufw allow 22/tcp comment 'SSH' >> "$JOURNAL"
  ufw allow 80/tcp comment 'HTTP Traefik' >> "$JOURNAL"
  ufw allow 443/tcp comment 'HTTPS Traefik' >> "$JOURNAL"
  ufw allow 443/udp comment 'HTTP/3 Traefik' >> "$JOURNAL"
  ufw allow 3000/tcp comment 'Dokploy temporaire' >> "$JOURNAL"
  ufw --force enable >> "$JOURNAL"
  ok "ufw : 22, 80, 443 (tcp et udp) et 3000 temporaire"

  # Sur Ubuntu 24.04 le service s'appelle ssh.service : sans ce réglage, fail2ban ne voit rien.
  cat > /etc/fail2ban/jail.d/99-bwf.local <<'EOT'
[sshd]
enabled      = true
backend      = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
maxretry     = 5
findtime     = 10m
bantime      = 1h
EOT
  fail2ban-client -t >> "$JOURNAL" 2>&1 || arret "configuration fail2ban invalide."
  systemctl enable fail2ban >> "$JOURNAL" 2>&1
  systemctl restart fail2ban
  sleep 2
  fail2ban-client status sshd >> "$JOURNAL" 2>&1 || arret "la prison sshd de fail2ban ne démarre pas."
  ok "fail2ban : 5 essais en 10 minutes, puis bannissement d'une heure"
  noter parefeu
}

journaux_docker() {
  fait journaux && return
  titre "Limite des journaux Docker"
  # Écrit avant Docker : tous les conteneurs, Traefik compris, naissent avec la limite.
  mkdir -p /etc/docker
  if [ -f /etc/docker/daemon.json ]; then cp -a /etc/docker/daemon.json "$SAUVEGARDE/daemon.json.avant"; fi
  cat > /etc/docker/daemon.json <<'EOT'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOT
  python3 -I -m json.tool /etc/docker/daemon.json > /dev/null || arret "daemon.json invalide."
  ok "Journaux limités à 3 fichiers de 10 Mo par conteneur"
  noter journaux
}

dokploy() {
  fait dokploy && { ok "Dokploy déjà installé"; return; }
  titre "Installation du panneau Dokploy (5 à 10 minutes)"
  curl -fsSL https://dokploy.com/install.sh -o "$SAUVEGARDE/dokploy-install.sh"
  info "Empreinte du script officiel : $(sha256sum "$SAUVEGARDE/dokploy-install.sh" | cut -c1-16)…"
  install -m 600 /dev/null "$SAUVEGARDE/dokploy-install.log"
  # La sortie contient le jeton du cluster Swarm : elle reste dans un fichier privé.
  sh "$SAUVEGARDE/dokploy-install.sh" >> "$SAUVEGARDE/dokploy-install.log" 2>&1 \
    || arret "l'installation de Dokploy a échoué. Détail : $SAUVEGARDE/dokploy-install.log"
  [ -d /etc/dokploy ] && chmod -R go-w /etc/dokploy
  info "Attente du panneau…"
  curl -s -o /dev/null --retry 40 --retry-delay 3 --retry-connrefused http://localhost:3000 \
    || arret "le panneau ne répond pas sur le port 3000."
  noter dokploy
  verifier_dokploy || arret "Dokploy est installé mais un contrôle a échoué (voir ci-dessus). Lance la procédure de secours du guide."
}

verifier_dokploy() {
  local ko=0
  for service in dokploy dokploy-postgres; do
    if docker service ls --format '{{.Name}} {{.Replicas}}' | grep -qx "$service 1/1"; then ok "Service $service 1/1"
    else info "${ROUGE}Service $service pas prêt${FIN}"; ko=1; fi
  done
  if docker ps --format '{{.Names}}' | grep -qx dokploy-traefik; then ok "Traefik tourne"
  else info "${ROUGE}Traefik ne tourne pas${FIN}"; ko=1; fi
  local c conf
  for c in $(docker ps --format '{{.Names}}'); do
    conf=$(docker inspect "$c" --format '{{json .HostConfig.LogConfig.Config}}')
    if [ "$conf" = '{"max-file":"3","max-size":"10m"}' ]; then ok "Journaux limités : $c"
    else info "${ROUGE}Journaux non limités : $c ($conf)${FIN}"; ko=1; fi
  done
  return $ko
}

compte_admin() {
  fait finalise && return
  titre "À faire tout de suite : crée ton compte administrateur"
  info "Ouvre  http://$(ip_publique):3000  dans ton navigateur et crée ton compte maintenant."
  info "Tant que ce n'est pas fait, la première personne qui ouvre cette page peut le créer."
  info "Mot de passe neuf, que tu n'utilises nulle part ailleurs, rangé dans ton gestionnaire."
  info ""
  info "Ensuite, dans le panneau : Settings, Web Server, Domain."
  info "Indique ton domaine du panneau (son enregistrement A doit pointer vers $(ip_publique)), ton email, HTTPS, Let's Encrypt."
  info "Quand https://TON-DOMAINE affiche le panneau avec le cadenas, lance :"
  info "    bash installer.sh finaliser TON-DOMAINE"
}

finaliser() {
  local domaine="${1:-}"
  [ -n "$domaine" ] || arret "indique le domaine du panneau : bash installer.sh finaliser panneau.mondomaine.com"
  fait dokploy || arret "Dokploy n'est pas encore installé. Lance d'abord : bash installer.sh"
  titre "Fermeture de l'accès direct au port 3000"
  local ip_dns ip_serveur code
  ip_serveur=$(ip_publique)
  ip_dns=$(getent ahostsv4 "$domaine" | awk 'NR==1 {print $1}')
  [ "$ip_dns" = "$ip_serveur" ] || arret "$domaine pointe vers « ${ip_dns:-rien} » au lieu de $ip_serveur. Corrige l'enregistrement A, attends quelques minutes, puis relance."
  ok "$domaine pointe vers ce serveur"
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://$domaine" || true)
  case "$code" in
    200|307|302) ok "https://$domaine répond ($code) avec un certificat valide" ;;
    *) arret "https://$domaine ne répond pas correctement (code « $code »). Le port 3000 reste ouvert : vérifie le domaine dans le panneau." ;;
  esac
  if docker service inspect dokploy --format '{{json .Endpoint.Ports}}' | grep -q '"PublishedPort":3000'; then
    docker service update --publish-rm "published=3000,target=3000,mode=host" dokploy >> "$JOURNAL" 2>&1
  fi
  ufw --force delete allow 3000/tcp >> "$JOURNAL" 2>&1 || true
  sleep 5
  code=$(curl -sS -o /dev/null -w '%{http_code}' --retry 20 --retry-delay 3 --retry-connrefused --retry-all-errors --max-time 15 "https://$domaine" || true)
  case "$code" in 200|307|302) ok "Le panneau répond toujours en HTTPS" ;; *) arret "le panneau ne répond plus en HTTPS (code « $code »). Rouvre l'accès : docker service update --publish-add published=3000,target=3000,mode=host dokploy" ;; esac
  [ "$(ss -tlnH '( sport = :3000 )' | wc -l)" -eq 0 ] && ok "Plus rien n'écoute sur le port 3000"
  echo "$domaine" > "$ETAT_DIR/domaine-panneau"
  noter finalise
  titre "Serveur prêt"
  info "Panneau : https://$domaine"
  info "Depuis ton ordinateur, vérifie que http://$ip_serveur:3000 ne charge plus."
}

verifier() {
  titre "État du serveur"
  sshd -T | grep -qx 'passwordauthentication no' && ok "SSH : mot de passe refusé" || info "${ROUGE}SSH : mot de passe accepté${FIN}"
  ufw status | grep -q 'Status: active' && ok "Pare-feu actif" || info "${ROUGE}Pare-feu inactif${FIN}"
  fail2ban-client status sshd > /dev/null 2>&1 && ok "fail2ban actif" || info "${ROUGE}fail2ban inactif${FIN}"
  [ "$(sysctl -n vm.swappiness)" = "10" ] && ok "swappiness 10" || info "swappiness $(sysctl -n vm.swappiness)"
  command -v docker > /dev/null && verifier_dokploy || true
  if [ -f "$ETAT_DIR/domaine-panneau" ]; then
    local d; d=$(cat "$ETAT_DIR/domaine-panneau")
    curl -s -o /dev/null --max-time 10 "https://$d" && ok "Panneau https://$d en ligne" || info "${ROUGE}Panneau https://$d injoignable${FIN}"
  fi
  info "Mémoire : $(free -h | awk '/Mem:/ {print $3" utilisés sur "$2}'). Disque : $(df -h --output=avail / | tail -1 | tr -d ' ') libres."
}

# ---------- programme ----------

case "${1:-installer}" in
  installer)
    prerequis
    systeme
    redemarrage
    memoire_echange
    ssh_par_cle
    pare_feu
    journaux_docker
    dokploy
    compte_admin
    ;;
  finaliser)
    [ "$(id -u)" -eq 0 ] || arret "lance le script en root."
    mkdir -p "$ETAT_DIR"; [ -f "$JOURNAL" ] || install -m 600 /dev/null "$JOURNAL"
    finaliser "${2:-}"
    ;;
  verifier) verifier ;;
  *) echo "Usage : bash installer.sh [installer | finaliser DOMAINE | verifier]"; exit 2 ;;
esac
