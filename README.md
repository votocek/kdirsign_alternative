# kdirsign_alternative
## Poslání
Skript, který nahrazuje činnost programu KDirSign (vyvinutý a používány na ČÚZK) pro podepsání výsledku zeměměřické činnosti. Je určen pro geodety, kteří pomocí něho připraví výsledky své činnosti pro odeslání na katastrální úřad.

## Úvod do problematiky
Geodeti před odevzdáním geometrického plánu (dále GP) v elektronické podobě na katastrální úřad musí nechat tento GP ověřit úředně oprávněným zeměmřickým inženýrem (dále ÚOZI). Během toho ověřování se kontroluje správnost a úplnost a jeho soulad s předpisy. Na závěr pak tento ÚOZI všechny elektronické podklady podepíše svým elektronickým podpisem (přesněji řečeno opatří jej zaručeným elektronickým podpisem založeným na kvalifikovaném certifikátu) a připojí i kvalifikované časové razítko.

Běžně se předávají tyto výstupy:
1. PDF soubor se žádostí o potvrzení GP - tento soubor stačí elektronicky podepsat
2. PDF soubor s vlastním GP - zde se kromě interního elektronického podpisu připojuje i interní kvalifikované časové razítko (interní znamená, že je součást souboru PDF)
3. ZPMZ (záznam podrobného měření změn) - sada několika souborů, která se opratřuje elektronickým podpisem i časovým razítkem v externím souboru

K podepsání prvních dvou položek (PDF souborů) se často používá program [JSignPDF](http://jsignpdf.sourceforge.net/), který je multiplatformní (napsán v jazyku JAVA) a zvládá přikládat jak elektronický podpis, tak i časové razítko.

Problém je třetí položka v seznamu výše - ZPMZ. K tomu zase moc programů neexistuje. ČÚZK k tomuto účelu vyvinul jednoduchý program nazvaný KDirSign. Najdeteho na stránkách úřadu:
[www.cuzk.cz | Je dobré vědět | Životní situace | Ověřování výsledků zeměměřických činností v elektronické podobě](https://www.cuzk.cz/Je-dobre-vedet/Zivotni-situace/Overovani-vysledku-zememerickych-cinnosti-v-elektr.aspx)

První verze byly psány v jazyce JAVA a fungovaly také na více platformách. Poslední verze z roku 2019 pak byla přepsána do jazyku C# a funguje patrně pouze na Windows. Protože používá:
* Windows Presentation Framework  (projekt MONO WFP nepodporuje - viz: https://www.mono-project.com/docs/gui/wpf/)
* Windows API k přístupu k uloženým certifikátům a poskytovatelům kryptografických funkcí

je pravděpodobné, že se nepodaří tento program zprovoznit na jiné platformě než MS Windows.

Já jsem potřeboval vyřešit podepisování na OS Linux. Proto jsem za pomoci původního autora KDirSign vytvořil tento skript v jazyce BASH, který dokáže nahradit základní funkci programu KDirSign. Skript lze po lehké úpravě přepsat tak, aby fungoval i v jiném shell interpretru - a třeba i ve Windows.

Jedná se spíše o základní funkční koncept než nějaký sofistikovaný program. Nicméně od září 2019 je lehce vylepšený skript používán běžně k "podepsání" ZPMZ, takže je tedy nasazen v produkčním provozu.

## Výsledek skriptu
Cílem je pro zadaný adresář (většinou pojmenovaný jako ZPMZ) vytvořit 3 soubory:
* Overeni_UOZI.txt       ... textový soubor s hlavičkou a obsahem adresáře
* Overeni_UOZI.txt.p7s   ... soubor s externím elektronickým podpisem
* Overeni_UOZI.txt.p7s.tsr  ... soubor s externím časovým razítkem

Na závěr pak skript obsah adresáře s nově vytvořenými soubory dle saznamu výše zabalí do ZIP archívu.


## Formát souboru Overeni_UOZI.txt
Příklad:
```
Náležitostmi a přesností odpovídá právním předpisům.
795/2019
2.10.2019
Ing. Aleš Votoček
----
770591_ZPMZ_00449_nacrt.pdf;372C59495E809F35362755C92D3B90E68BAD47651748067CAED8897B30A3B402BC97D86F90815A7813DB9B1EA2E1CE29650E9F1288A12CA2D8AE9C0E6E565CC7
770591_ZPMZ_00449_popispole.pdf;133C9CD2F8E8EA684E2DA12208346E630C5F611CC1429EEF0A4A0BE41ADC4953721494DD7F158660D898A628EA7599149E152FAF9F62C624D53BB8CDD08FA7F8
770591_ZPMZ_00449_prot.pdf;A4BA7ABE4C31C0A92DCA3F72FC122DAB2F1BAE9022E96CB258F50B35F81DCA22547B80BBF0E45644B5609AF14E4EFD8B15E7260E3936B7467DFD5624AD63D215
770591_ZPMZ_00449_ss.txt;7B0A44ED6A605F11244B19D42CDFB2B1A8B07ACD5126D095A0E3A44FD932DF01BCD969EBE5ED4A656DC1A3DA46886C1B298A4DDE37293D253612FF80610FA29E
770591_ZPMZ_00449_vfk.vfk;95BBA3B1F8C9D585F7E9E2231082790663D072656D073D38B2756D9ED605AC72F026244DB35CBD818960303D98407FBEEED0B3A955115B5D1CD56A2C503F05F2
770591_ZPMZ_00449_vymery.pdf;2FBE588417950DB5297FF8F1DBE403977138157010E56AF55564CF7AD93BF0D9C63624C30DF9E9170D8C4CA567000520AAD710ED90DB57C328196F673EBEDDDE
770591_ZPMZ_00449_zap.pdf;23342FAE6295BFB538F9CDD3B8305EC1E9E86E19F0EB7CE22574766FF963C83FA3C539B598717679AA45B8110718C3F3B6253635E3AED75E2E34529D847416EC
```

## Základní flow ve skriptu
Hlavní funkce ve skriptu spočívá v následujícím.

1. Vytvoř hlavičku v souboru Overeni_UOZI.txt  
První řádek souboru by měl vypadat vždy takto:
```    
    Náležitostmi a přesností odpovídá právním předpisům.
```

2. Zapiš číslo z evidence ve formátu pořadové číslo / rok.  
Číslo zadává geodet dle své evidence. Např.
```
    795/2019
```

3. Zapiš na další řádek datum.  
Formát DD.MM.YYYY
```
   2.10.2019
```

4. Zapiš jméno geodeta (úředně oprávněného zěměměřického inženýra), který bude podepisovat.   
Jak získat jméno geodeta - úředně oprávněného inženýra?   
  * Nejjednodušší implementace: jméno bude napevno zapsáno ve skritpu.
  * Případně se zeptat na jméno či přečíst z nějaké globální konfigurace.
  * Nejjlepší způsob je ho extrahovat z certifikátu použitého pro elektronický podpis.

Např.:
```
    Ing. Aleš Votoček
```

5. Zapiš řádek s oddělovači  
Přesně 4 znaky:
```
    ----
```

6. Pro každý soubor v adresáři rekurzivně zapiš název, znak středník a SHA512 checksum (znaky šestnáckové číselné soustavy pomocí velkých písmen).   
Např.:
```
770591_ZPMZ_00449_nacrt.pdf;372C59495E809F35362755C92D3B90E68BAD47651748067CAED8897B30A3B402BC97D86F90815A7813DB9B1EA2E1CE29650E9F1288A12CA2D8AE9C0E6E565CC7
```

7. Vytvoř externí soubor s elektronickým podpisem
```
openssl smime -sign -binary -in file -signer certificate.pem -inkey key.pem -outform DER -out file.p7s
```
* certificate.pem    ... veřejný certifikát podepsaný certifikační autoritou ve formátu PEM (textový formát kódovaný pomocí Base64)
* key.pem            ... privátní klíč k certifikátu ve formátu PEM

Openssl zvládá číst více formátu. Můžete vyzkoušet jiné formáty zabezpečené heslem.

8. Přilož kvalifikované časové razítko   
* V první fázi vytvoř žádost o časové razítko:
```
openssl ts -query -data "file.p7s" -cert -sha256 -out request.tsq
```

* Vdruhé fázi odešli žádost na certifikančí autoritu vydávající časová razítka  
Použij wget / curl programy. Je to v podstatě jen o adrese, přihlašovacích údajích, a přiložených datech.
```
curl -k -u "<TSA přihlašovací údaje>" -H "Content-Type: application/timestamp-query" --data-binary @"request.tsq" -X POST "${TSA_URL}"  > "Overeni_UOZI.txt.p7s.tsr"

# Napr. pro testovací CA u PostSignum:
curl -k -u demoTSA:demoTSA2010 -H "Content-Type: application/timestamp-query" --data-binary @request.tsq -X POST "https://www3.postsignum.cz/DEMOTSA/TSS_user/"  >file.tsr
```
