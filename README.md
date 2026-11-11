# Serveur Build with Fèmi

Ton propre panneau de déploiement, façon Vercel, sur ton serveur. Une commande installe tout : sécurité, Docker et le panneau [Dokploy](https://dokploy.com). Ensuite, tu mets tes outils en ligne depuis GitHub, en quelques clics.

Testé sur Ubuntu 24.04, chez mvps.net, en novembre 2026.

## Ce qu'il te faut

- Un serveur VPS **Ubuntu 24.04** avec **au moins 2 Go de mémoire** et 25 Go de disque. 4 Go et 40 Go de disque sont conseillés dès que plusieurs outils tournent.
- Un nom de domaine. Tu y crées un enregistrement **A** `panneau` qui pointe vers l'adresse IP du serveur.
- Un ordinateur sous Windows, Mac ou Linux. Rien à installer : le terminal suffit.

## 1. Envoyer ta clé SSH au serveur (sur ton ordinateur)

La clé remplace le mot de passe : personne ne pourra entrer sur ton serveur sans elle.

**Mac ou Linux**, dans le Terminal :

```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "ton@email.com"
ssh-copy-id root@IP_DU_SERVEUR
```

**Windows**, dans PowerShell :

```powershell
if (!(Test-Path $env:USERPROFILE\.ssh\id_ed25519.pub)) { ssh-keygen -t ed25519 -C "ton@email.com" }
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@IP_DU_SERVEUR "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Le serveur te demande une dernière fois le mot de passe root fourni par ton hébergeur. Ensuite, `ssh root@IP_DU_SERVEUR` doit te connecter sans mot de passe.

## 2. Installer (sur le serveur)

```bash
ssh root@IP_DU_SERVEUR
curl -fsSL https://raw.githubusercontent.com/build-with-femi/serveur/main/installer.sh -o installer.sh
bash installer.sh
```

Colle ces commandes une ligne à la fois : la connexion `ssh` doit être ouverte avant de lancer les suivantes.

Le script fait tout seul :

1. vérifie le serveur (Ubuntu, mémoire, disque, ports libres, clé SSH présente) ;
2. met le système à jour et active les mises à jour de sécurité automatiques ;
3. règle la mémoire d'échange ;
4. passe SSH en connexion par clé uniquement ;
5. active le pare-feu et la protection contre les essais de mot de passe (fail2ban) ;
6. limite la taille des journaux Docker ;
7. installe Dokploy.

Il s'arrête seulement quand il a besoin de toi :

- **le nom du serveur** (Entrée pour garder celui proposé) ;
- **un redémarrage**, si une mise à jour l'exige : reconnecte-toi et relance `bash installer.sh`, il reprend où il en était ;
- **tes clés** : vérifie que chaque empreinte affichée est bien la tienne ;
- **la deuxième connexion** : avant de couper le mot de passe, il te demande de vérifier dans un autre terminal que ta clé marche. Si tu ne réponds pas OUI, il annule tout.

## 3. Créer ton compte et donner un domaine au panneau

À la fin, le script affiche `http://IP_DU_SERVEUR:3000`.

1. **Ouvre cette adresse tout de suite et crée ton compte administrateur.** Tant que ce n'est pas fait, n'importe qui peut le créer.
2. Dans le panneau : **Settings**, **Web Server**, **Domain**. Indique `panneau.tondomaine.com`, ton email, active HTTPS et choisis Let's Encrypt.
3. Ouvre `https://panneau.tondomaine.com` : le cadenas doit s'afficher.

## 4. Fermer l'accès direct (sur le serveur)

```bash
bash installer.sh finaliser panneau.tondomaine.com
```

Le script vérifie que le domaine pointe vers le serveur et que le HTTPS répond, puis ferme le port 3000. Si une vérification échoue, il ne ferme rien.

## À tout moment

```bash
bash installer.sh verifier
```

Affiche l'état du serveur : SSH, pare-feu, fail2ban, Dokploy, panneau en ligne, mémoire et disque libres.

Journal complet : `/var/log/bwf-installation.log`. Fichiers privés (jeton du cluster, sauvegardes) : `/root/bwf-backup/`, à ne jamais partager.
