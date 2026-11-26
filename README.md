<div align="center">

# mach1ne_counterfeit

**Falskmøntneri til FiveM.** Tryk, tør, skær og bundt dine egne falske sedler i et værksted, du bygger hvor du vil.

![FiveM](https://img.shields.io/badge/FiveM-cerulean-F40552?style=flat-square)
![ESX](https://img.shields.io/badge/framework-ESX-2C3E50?style=flat-square)
![ox_inventory](https://img.shields.io/badge/inventory-ox__inventory-1F6FEB?style=flat-square)
![st_libs](https://img.shields.io/badge/UI-st__libs-8957E5?style=flat-square)
![Sprog](https://img.shields.io/badge/sprog-da%20%7C%20en-2EA043?style=flat-square)

<img src="anim_preview.gif" width="49%" alt="Maskinernes animationer"> <img src="ped_anim_preview.gif" width="49%" alt="Spillerens animationer">

</div>

---

## Indhold

- [Features](#features)
- [Produktionen](#produktionen)
- [Installation](#installation)
- [Sådan spiller det](#sådan-spiller-det)
- [Politiet](#politiet)
- [Konfiguration](#konfiguration)
- [Animationer](#animationer)
- [Ydelse](#ydelse)

## Features

- **Fire maskiner med egne modeller**: trykpresse, tørresnor, skæremaskine og sedeltæller, plus et arbejdsbord. De skifter model efter, hvor langt de er.
- **Maskiner der bevæger sig**: valserne drejer, arkene svajer på snoren, kniven skærer, og sedlerne bladres gennem tælleren.
- **Animationer til spilleren** lavet til hver maskine. Hænderne griber om håndtaget, papiret og bunkerne, og alle omkring dig ser det i takt.
- **Byg dit værksted hvor som helst**: ude, inde, i housing og oven på andre ting, f.eks. en sedeltæller på et bord.
- **Serienumre** på hvert bundt, gemt i databasen, så politiet kan spore hvor og hvornår sedlerne blev lavet.
- **Støj**: pressen larmer, og naboerne ringer til politiet.
- **Hæler-NPC**, der sælger udstyr og køber bundterne for sorte penge.
- **Dansk og engelsk** via st_libs locale.

## Produktionen

| # | Maskine | Input | Output | Tid |
| :-: | --- | --- | --- | --- |
| 1 | **Trykpresse** | 2× Bomuldspapir + 1× Sikkerhedsblæk | 2× Våde trykark | 6 min |
| 2 | **Tørresnor** | 2× Våde trykark | 2× Trykark | 8 min |
| 3 | **Skæremaskine** | 1× Trykark | 8× Løse sedler | 5 s |
| 4 | **Sedeltæller** | 25× Løse sedler + 1× Banderole | 1× Bundt (med serienummer) | 4 s |
| 5 | **Hæleren** | Bundt | 45 % af pålydende i sorte penge | |

Mængder og tider gælder pr. portion, og en maskine tager så mange portioner, som du har materialer til. Alt kan ændres i `config.lua`.

> **Pressen og tørresnoren** er tidsstyrede: fyld dem, gå fra dem og kom tilbage. Glemmer du de våde ark i pressen, klistrer halvdelen sammen.
>
> **Skæremaskinen og sedeltælleren** er aktive: du står ved dem, mens de arbejder, og får outputtet direkte. Afbryder du, får du materialerne tilbage.

## Installation

**Krav:** [es_extended](https://github.com/esx-framework/esx_core) · [ox_lib](https://github.com/overextended/ox_lib) · [ox_inventory](https://github.com/overextended/ox_inventory) · [oxmysql](https://github.com/overextended/oxmysql) · st_libs

1. Læg mappen `mach1ne_counterfeit` i din `resources`-mappe.
2. Tilføj items i ox_inventory:
   - Indsæt blokken fra [`install/ox_inventory/items.lua`](install/ox_inventory/items.lua) i `ox_inventory/data/items.lua` (inden den sidste `}`).
   - Kopiér billederne fra [`install/ox_inventory/images/`](install/ox_inventory/images) til `ox_inventory/web/images/`.
3. Tilføj til `server.cfg` efter afhængighederne:

   ```cfg
   ensure mach1ne_counterfeit
   ```

4. Start serveren. Databasetabellerne oprettes automatisk ([`sql/install.sql`](sql/install.sql) findes også).

> [!NOTE]
> Hæleren står som standard på Elysian Island. Ret `Config.Dealer.coords`, hvis han skal stå et andet sted.
> UV-scanneren (`cf_scanner`) sælges ikke af hæleren, så læg den i politiets armory eller shop.

## Sådan spiller det

Køb udstyr og materialer hos hæleren, og brug maskinerne fra inventaret for at stille dem op.

**Placering**

| Tast | Handling |
| --- | --- |
| `E` | Placér |
| `←` `→` | Rotér (hold `Shift` for fin rotation) |
| `Scroll` | Hæv / sænk |
| `Backspace` / højreklik | Annullér |

**Ved maskinerne**

| Objekt | `E` | `G` (ejer) | `H` (politi) |
| --- | --- | --- | --- |
| Trykpresse / tørresnor | Fyld · se tid · tøm | Pak sammen (når den er tom) | Beslaglæg |
| Skæremaskine / sedeltæller | Arbejd ved maskinen | Pak sammen | Beslaglæg |
| Arbejdsbord | | Pak sammen | Beslaglæg |

Maskinerne er kun synlige i den routing bucket, de er stillet op i. Et værksted i en housing-instance er altså kun synligt for dem, der er inde i den.

## Politiet

- **Naboer ringer**: mens en presse kører, er der en lille chance hvert minut for, at politiet får et område markeret på kortet.
- **UV-scanner**: alle kan se, at deres bundter er falske. Betjente ser også, hvornår hver serie blev talt op, i hvilket område, og om sedeltælleren stadig står der. De kan sætte et omtrentligt waypoint.
- **Beslaglæggelse**: `H` ved en maskine fjerner den.

## Konfiguration

Alt står i [`config.lua`](config.lua):

| Indstilling | Hvad den styrer |
| --- | --- |
| `Config.Locale` | Sprog (`da` / `en`). Teksterne ligger i [`locales/`](locales) |
| `Config.Stations` | Input, output, tider, modeller og arbejdspositioner for hver maskine |
| `Config.Bundle` | Antal sedler pr. bundt og pålydende |
| `Config.Noise` | Chancen for at naboerne ringer, og cooldown |
| `Config.Police` | Politijobs og blip |
| `Config.Dealer` | Hælerens position, varer, priser og hvor meget han betaler |
| `Config.StationLimits` / `Config.Props` | Maks antal maskiner pr. spiller |

## Animationer

<details>
<summary><b>Maskinerne</b> (<code>stream/m1_cf_anims.ycd</code>)</summary>

<br>

| Clip | Længde | Hvad sker der |
| --- | --- | --- |
| `press_run` | 2 s loop | Valser, svinghjul og tandhjul drejer. Et ark kører ind bagfra og lander i bakken |
| `dryline_sway` | 4 s loop | 10 ark svajer i vinden, hver i sin egen takt |
| `cutter_cut` | 2,5 s loop | Pressebjælken spænder, armen trækkes ned, kniven skærer, og en strimmel sedler glider frem |
| `counter_count` | 1 s loop | Valsen drejer, og sedlerne vipper ned i maskinen og glider ud i lommen |

</details>

<details>
<summary><b>Spilleren</b> (<code>stream/m1_cf_ped.ycd</code>)</summary>

<br>

| Clip | Maskine | Hvad spilleren gør |
| --- | --- | --- |
| `cut` | Skæremaskine | Begge hænder på håndtaget og trækker ned i takt med kniven |
| `count` | Sedeltæller | Holder bunken i tragten og retter sedlerne til i lommen |
| `press_feed` | Trykpresse, bagpå | Retter papirstakken til og skubber den ind |
| `press_take` | Trykpresse, foran | Bukker sig ned og løfter bunken op fra bakken |
| `hang` | Tørresnor | Rækker op og sætter arket i klemmerne |

</details>

Spilleren bliver stillet præcist foran maskinen, og maskinens animation starter samtidig. Serveren sender starttidspunktet videre, så andre spillere også ser kniven gå ned i takt med armene.

> [!IMPORTANT]
> Spillerens animationer er lavet til arbejdspositionerne i `config.lua`, og sedeltælleren til et bord i 0,9 m højde (arbejdsbordet). Flytter du positionerne, passer hænderne ikke længere.

Findes en model ikke, bruges en vanilla-prop i stedet, men så uden animation.

## Ydelse

- Alle modeller deler én texture dictionary (`m1_cf_tex.ytd`), så teksturerne kun hentes én gang.
- Hver model har en forenklet LOD. Fuld detalje vises op til 15 m, den forenklede op til 70 m, og sedeltælleren forsvinder allerede ved 35 m.
- 3D-teksten ved maskinerne bygges kun om, når maskinens tilstand ændrer sig.

---

<div align="center">

Lavet af **TheMach1neDK**

</div>
