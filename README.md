# BitwardenBackup

## Table of contents

- [Introduction](#introduction)
- [Setup](#setup)
- [Usage](#usage)
- [License](#license)

## Introduction

[Bitwarden](https://bitwarden.com/) is a password manager. If you're using the cloud-hosted version, you should be doing regular backups.

You can do that manually with [this guide](https://bitwarden.com/resources/guide-how-to-create-and-store-a-backup-of-your-bitwarden-vault/), or automate it with this script.

## Setup

Note that only Windows is currently supported.

Requirements:
* [Powershell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) or higher
* [Bitwarden Desktop](https://bitwarden.com/download/) - must be logged in (but you can leave the vault locked)
* [Healthchecks.io](https://healthchecks.io/) - create an account and create checks called `bitwarden-backup` and `bitwarden-backup-recent`

Clone this repo anywhere you like using:
```ps1
git clone https://github.com/davidtorosyan/BitwardenBackup.git
```

## Usage

Run the script:
```ps1
.\src\Backup-Bitwarden.ps1
```

The first time you run, this will:
1. Prompt you for a Healthchecks ping key
2. Create a scheduled task that runs daily

On every run (including the first), this will:
1. Copy the encrypted secrets vault to `%AppData%\Roaming\BitwardenBackup\backups`
2. Timestamp the file with the sync time
3. Prune old backups using a hardcoded retention policy
4. Send health pings

Since the vault is encrypted, the backups are fairly safe, but don't share them widely.

In the event you need to recover your vault, you can use a tool like [BitwardenDecrypt](https://github.com/GurpreetKang/BitwardenDecrypt).

## License
[MIT](https://choosealicense.com/licenses/mit/)
