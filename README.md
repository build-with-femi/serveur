# Serveur Build with Fèmi

Ton propre panneau de déploiement, façon Vercel, sur ton serveur. Une commande installe tout : sécurité, Docker et le panneau [Dokploy](https://dokploy.com). Ensuite, tu mets tes outils en ligne depuis GitHub, en quelques clics.

Testé sur Ubuntu 24.04, chez mvps.net, en novembre 2026. Durée : 30 à 45 minutes, dont 10 où tu attends.

## Ce qu'il te faut

- Un serveur VPS **Ubuntu 24.04** avec **au moins 2 Go de mémoire** et 25 Go de disque. 4 Go et 40 Go de disque sont conseillés dès que plusieurs outils tournent. Note son **adresse IP** et le **mot de passe root** que l'hébergeur affiche.
- Un nom de domaine, par exemple `tondomaine.com`.
- Un ordinateur sous Windows, Mac ou Linux. Rien à installer : le terminal suffit.

Dans ce guide, remplace `IP_DU_SERVEUR` par l'adresse de ton serveur et `tondomaine.com` par ton domaine.

> **Règle d'or** : colle les commandes **une ligne à la fois**, et attends que chacune ait fini avant la suivante.

## 0. Pointer ton domaine vers le serveur (chez ton registrar)

Fais-le en premier : la propagation peut prendre de quelques minutes à une heure.

Dans la gestion DNS de ton domaine (chez Hostinger : Noms de domaine, ton domaine, DNS / Serveurs de noms) :

| Type | Nom | Valeur | TTL |
| --- | --- | --- | --- |
| A | `panneau` | `IP_DU_SERVEUR` | 300 |
| A | `@` | `IP_DU_SERVEUR` | 300 |

S'il existe déjà un A `@` (souvent une page de parking), **modifie-le** au lieu d'en ajouter un deuxième. Supprime tout enregistrement **AAAA** sur `@` ou `panneau` : il empêcherait le certificat HTTPS. Ne touche pas aux autres enregistrements (emails, TXT).

## 1. Envoyer ta clé SSH au serveur (sur ton ordinateur)

La clé remplace le mot de passe : personne ne pourra entrer sur ton serveur sans elle. C'est la **dernière fois** que tu tapes le mot de passe root.

**Mac ou Linux**, dans le Terminal :

```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "ton@email.com"
```
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@IP_DU_SERVEUR
```

**Windows**, dans PowerShell :

```powershell
if (!(Test-Path $env:USERPROFILE\.ssh\id_ed25519.pub)) { ssh-keygen -t ed25519 -C "ton@email.com" }
```
```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@IP_DU_SERVEUR "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

- `ssh-keygen` te demande où enregistrer la clé (appuie sur Entrée) et une phrase secrète (conseillé : choisis-en une et garde-la).
- À la première connexion, ton ordinateur demande `Are you sure you want to continue connecting (yes/no)?` : tape `yes`.
- Puis il demande le mot de passe root de l'hébergeur : colle-le (rien ne s'affiche quand tu tapes, c'est normal) et appuie sur Entrée.

**Vérifie** : `ssh root@IP_DU_SERVEUR` doit maintenant te connecter **sans** mot de passe root. Tape `exit` pour revenir sur ton ordinateur.

Si tu as réinstallé le serveur et que ton ordinateur affiche `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`, lance `ssh-keygen -R IP_DU_SERVEUR`, puis recommence.

## 2. Installer (sur le serveur)

Connecte-toi, puis télécharge et lance le script, une ligne à la fois :

```bash
ssh root@IP_DU_SERVEUR
```
```bash
curl -fsSL https://raw.githubusercontent.com/build-with-femi/serveur/main/installer.sh -o installer.sh
```
```bash
bash installer.sh
```

Les lignes en orange commençant par `>` annoncent chaque étape ; `OK` en vert confirme qu'elle a réussi. Le script s'arrête seulement quand il a besoin de toi, à quatre moments.

### Moment 1 : le nom du serveur

`Nom de ce serveur (...) :` Tape un nom court (par exemple `boutique`) ou appuie sur **Entrée** pour garder `bwf-serveur`.

### Moment 2 : le redémarrage (presque toujours, la première fois)

`Redémarrer maintenant ? ... Tape OUI pour continuer :` Tape `OUI`. Ta connexion se coupe, c'est prévu.

Attends **une minute**, puis reconnecte-toi et relance le script (inutile de le retélécharger) :

```bash
ssh root@IP_DU_SERVEUR
```
```bash
bash installer.sh
```

Il reprend où il en était : les étapes déjà faites affichent `OK ... déjà ...`.

### Moment 3 : tes clés

Le script affiche les clés autorisées sur le serveur, par exemple :

```
256 SHA256:Vf+bqWGC8SVZ... ton@email.com (ED25519)
```

Sur **ton ordinateur**, dans une autre fenêtre de terminal, affiche l'empreinte de ta clé :

```bash
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

(Windows : `ssh-keygen -lf $env:USERPROFILE\.ssh\id_ed25519.pub`)

Le `SHA256:...` doit être **identique**. Si toutes les lignes affichées sont à toi, tape `OUI`. S'il y a une clé que tu ne reconnais pas, ne tape rien d'autre que Entrée : le script s'arrête sans rien changer.

### Moment 4 : la deuxième connexion

Avant de couper définitivement le mot de passe, le script vérifie que ta clé marche. **Garde la fenêtre du serveur ouverte**, ouvre une **nouvelle** fenêtre de terminal sur ton ordinateur et lance les deux commandes qu'il affiche :

```bash
ssh root@IP_DU_SERVEUR
```
→ tu dois arriver sur le serveur sans mot de passe. Tape `exit`.

```bash
ssh -o PubkeyAuthentication=no root@IP_DU_SERVEUR
```
→ la réponse doit être `Permission denied (publickey)`.

Si les deux résultats sont ceux-là, reviens dans la fenêtre du serveur et tape `OUI`. Sinon, tape Entrée : le script remet tout comme avant et tu ne perds pas l'accès.

### Ensuite : patiente

Le script installe le pare-feu, la protection fail2ban, puis **Dokploy** (`Installation du panneau Dokploy (5 à 10 minutes)`). Ne ferme pas la fenêtre et ne tape rien. À la fin, il affiche :

```
> À faire tout de suite : crée ton compte administrateur
  Ouvre  http://IP_DU_SERVEUR:3000  dans ton navigateur ...
```

## 3. Créer ton compte et donner un domaine au panneau

1. **Ouvre `http://IP_DU_SERVEUR:3000` tout de suite et crée ton compte administrateur.** Tant que ce n'est pas fait, n'importe qui peut le créer. Prends un mot de passe neuf, que tu n'utilises nulle part ailleurs, et range-le dans ton gestionnaire de mots de passe.
2. Si un écran d'accueil propose de choisir une offre, clique sur **Skip** : ta version, installée sur ton serveur, est gratuite.
3. Dans le menu : **Settings**, puis **Web Server**. Dans le bloc du domaine du serveur :
   - Domain : `panneau.tondomaine.com`
   - Let's Encrypt Email : ton email (pour les alertes du certificat)
   - HTTPS : activé
   - Certificate : Let's Encrypt
4. Enregistre, attends une minute, puis ouvre `https://panneau.tondomaine.com`. Le cadenas doit s'afficher et tu dois pouvoir te connecter.

Si le cadenas n'apparaît pas après 5 minutes : vérifie l'enregistrement A `panneau` (étape 0) et l'absence d'AAAA. Ne passe pas à l'étape 4 tant que le HTTPS ne marche pas.

## 4. Fermer l'accès direct (sur le serveur)

Dans la fenêtre du serveur :

```bash
bash installer.sh finaliser panneau.tondomaine.com
```

Le script vérifie que le domaine pointe vers ce serveur et que le HTTPS répond, puis ferme le port 3000. Si une vérification échoue, il ne ferme rien et te dit quoi corriger.

**Vérifie depuis ton ordinateur** : `http://IP_DU_SERVEUR:3000` ne doit plus s'ouvrir dans ton navigateur, et `https://panneau.tondomaine.com` doit toujours marcher.

## À tout moment

```bash
bash installer.sh verifier
```

Affiche l'état du serveur : SSH, pare-feu, fail2ban, Dokploy, panneau en ligne, mémoire et disque libres.

## En cas de problème

Le script ne fait rien de dangereux en silence : s'il s'arrête, il dit pourquoi en rouge. Corrige ce qu'il indique, puis relance `bash installer.sh` ; les étapes déjà faites sont sautées.

Pour demander de l'aide, envoie :
- le message rouge affiché ;
- la fin du journal : `tail -40 /var/log/bwf-installation.log`.

N'envoie jamais le contenu de `/root/bwf-backup/` : il contient le jeton de ton serveur.
