<div align="center">

# mach1ne_counterfeit

**Lav falske penge i FiveM.** Print sedlerne, tør dem, skær dem ud og pak dem i bundter. Du bygger selv dit værksted, hvor du vil.

![FiveM](https://img.shields.io/badge/FiveM-cerulean-F40552?style=flat-square)
![ESX](https://img.shields.io/badge/framework-ESX-2C3E50?style=flat-square)
![ox_inventory](https://img.shields.io/badge/inventory-ox__inventory-1F6FEB?style=flat-square)
![st_libs](https://img.shields.io/badge/UI-st__libs-8957E5?style=flat-square)
![Sprog](https://img.shields.io/badge/sprog-da%20%7C%20en-2EA043?style=flat-square)

<img src="anim_preview.gif" width="49%" alt="Maskinerne i gang"> <img src="ped_anim_preview.gif" width="49%" alt="Spilleren ved maskinerne">

</div>

---

## Indhold

- [Sådan laver du pengene](#sådan-laver-du-pengene)
- [Installation](#installation)
- [Styring](#styring)
- [Skærmene](#skærmene)
- [Politiet](#politiet)
- [Indstillinger](#indstillinger)
- [Animationer](#animationer)

## Sådan laver du pengene

| Trin | Maskine | Du skal bruge | Du får | Tid |
| :-: | --- | --- | --- | --- |
| 1 | **Trykpresse** | 2 bomuldspapir + 1 blæk | 2 våde ark | 6 min |
| 2 | **Tørresnor** | 2 våde ark | 2 tørre ark | 8 min |
| 3 | **Skæremaskine** | 1 tørt ark | 8 sedler | 5 sek |
| 4 | **Sedeltæller** | 25 sedler + 1 papirbånd | 1 bundt | 4 sek |
| 5 | **Hæleren** | Bundter | Sorte penge (ca. 45 % af værdien, svinger) | |

Har du materialer nok, kan du lave flere ad gangen. Alle tal kan ændres i `config.lua`.

> **Trykpressen og tørresnoren** passer sig selv. Fyld dem, gå din vej, og kom tilbage, når de er færdige. Men glem ikke de våde ark i pressen for længe, for så klistrer halvdelen sammen.
>
> **Ved skæremaskinen og sedeltælleren** skal du blive stående, mens de arbejder. Går du, får du dine ting tilbage.

## Installation

**Du skal have:** [es_extended](https://github.com/esx-framework/esx_core), [ox_lib](https://github.com/overextended/ox_lib), [ox_inventory](https://github.com/overextended/ox_inventory), [oxmysql](https://github.com/overextended/oxmysql) og st_libs.

1. Læg mappen `mach1ne_counterfeit` i din `resources`-mappe.
2. Tilføj tingene til ox_inventory:
   - Kopiér teksten fra [`install/ox_inventory/items.lua`](install/ox_inventory/items.lua) ind i `ox_inventory/data/items.lua`, lige før den sidste `}`.
   - Kopiér billederne fra [`install/ox_inventory/images/`](install/ox_inventory/images) over i `ox_inventory/web/images/`.
3. Skriv det her i din `server.cfg` (under de andre scripts, den bruger):

   ```cfg
   ensure mach1ne_counterfeit
   ```

4. Start serveren. Databasen sætter sig selv op første gang.

> [!NOTE]
> Hæleren står på Elysian Island. Du kan flytte ham i `config.lua` under `Config.Dealer`.
> UV-scannerne (`cf_scanner` til lommen og `cf_uvscanner` til bordet) kan ikke købes hos hæleren. Giv dem til politiet, f.eks. i deres våbenlager.
>
> Bruger du ox_target, skal den startes før `mach1ne_counterfeit`. Vil du hellere have 3D-tekst, så sæt `Config.Interaction = 'st_libs'`.

## Styring

**Når du stiller noget op**

| Tast | Hvad sker der |
| --- | --- |
| `E` | Stil det her |
| `←` `→` | Drej (hold `Shift` for at dreje langsomt) |
| `Scroll` | Op og ned |
| `Backspace` eller højreklik | Fortryd |

**Ved maskinerne**

Med ox_target sigter du bare på tingen og vælger i menuen. Med 3D-tekst bruger du tasterne herunder.

| | `E` | `G` (kun ejeren) | `H` (kun politi) |
| --- | --- | --- | --- |
| Trykpresse og tørresnor | Fyld, se tid eller tøm | Pak sammen (skal være tom) | Beslaglæg |
| Skæremaskine og sedeltæller | Gå i gang | Pak sammen | Beslaglæg |
| Arbejdsbord | | Pak sammen | Beslaglæg |
| Laptop | Se dine maskiner | Pak sammen | Beslaglæg |
| UV-scanner (bord) | Scan bundter (kun politi) | Pak sammen | |

Står dit værksted inde i et hus, kan kun folk, der er inde i huset, se det.

## Skærmene

Flere af tingene har en skærm, der viser hvad der sker lige nu:

| Ting | Skærmen viser |
| --- | --- |
| **Sedeltæller** | Tæller sedlerne op, mens den kører, og viser bagefter serienummeret på bundtet |
| **Tørresnor** | En fugtmåler, der falder, mens arkene tørrer, og skriver *TØR*, når de er klar |
| **Laptop** | Alle maskiner i nærheden: om de er tomme, kører eller er færdige, og hvor lang tid der er tilbage |
| **UV-scanner (bord)** | Resultatet af politiets seneste scanning: *FALSK*, serienummer, område og dato |
| **Kurstavle ved hæleren** | Hvad han betaler for et bundt lige nu, om prisen er på vej op eller ned, og hvor stor efterspørgslen er |

Står der flere af samme slags, er det den, du står tættest på, der er tændt.

**Hælerens pris** falder, når der bliver solgt mange bundter, og stiger langsomt igen, når der er roligt. Det kan du justere under `Config.Dealer.sell`.

## Politiet

- **Naboerne ringer:** mens pressen kører, kan politiet få et område vist på kortet.
- **UV-scanner i lommen:** alle kan se, at sedlerne er falske. Politiet kan også se, hvornår bundtet blev lavet, og cirka hvor. De kan sætte et punkt på kortet.
- **UV-scanner på bordet:** politiet kan stille en scanner op på stationen. Resultatet kommer også op på scannerens skærm, så kollegaerne kan se med.
- **Beslaglæg:** tryk `H` ved en maskine for at tage den.

## Indstillinger

Alt kan ændres i [`config.lua`](config.lua):

| Indstilling | Hvad den gør |
| --- | --- |
| `Config.Locale` | Sproget: `da` eller `en`. Teksterne ligger i [`locales/`](locales) |
| `Config.Interaction` | `'ox_target'` eller `'st_libs'` (3D-tekst) |
| `Config.Screens` | Slå skærmene til og fra, og hvor tæt på man skal være |
| `Config.Stations` | Hvad maskinerne skal bruge, hvad de giver, og hvor lang tid det tager |
| `Config.Bundle` | Hvor mange sedler der er i et bundt, og hvad det er værd |
| `Config.Noise` | Hvor tit naboerne ringer |
| `Config.Police` | Hvilke jobs der tæller som politi |
| `Config.Dealer` | Hvor hæleren og kurstavlen står, hvad han sælger, og hvordan prisen svinger |
| `Config.StationLimits` og `Config.Props` | Hvor mange maskiner hver spiller må have |

## Animationer

Maskinerne og din figur bevæger sig i takt. Når du trækker i håndtaget, går kniven ned, og det ser alle omkring dig.

<details>
<summary><b>Maskinerne</b></summary>

<br>

| Maskine | Hvad sker der |
| --- | --- |
| Trykpresse | Valserne og svinghjulet drejer, og et ark kører igennem og lander i bakken |
| Tørresnor | Sedlerne svajer i vinden |
| Skæremaskine | Armen går ned, kniven skærer, og en stribe sedler glider frem |
| Sedeltæller | Sedlerne bladres ned i maskinen og kommer ud foran |

</details>

<details>
<summary><b>Din figur</b></summary>

<br>

| Maskine | Hvad du gør |
| --- | --- |
| Skæremaskine | Tager fat med begge hænder og trækker håndtaget ned |
| Sedeltæller | Holder bunken og retter sedlerne til |
| Trykpresse, bagfra | Retter papiret til og skubber det ind |
| Trykpresse, forfra | Bukker dig ned og løfter bunken op |
| Tørresnor | Rækker op og hænger arket op |

</details>

> [!IMPORTANT]
> Animationerne passer til de pladser, der står i `config.lua`. Sedeltælleren skal stå på arbejdsbordet. Flytter du på pladserne, rammer hænderne ved siden af.

---

<div align="center">

Lavet af **TheMach1neDK**

</div>
