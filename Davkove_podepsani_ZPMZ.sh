#!/bin/bash
# Davkovy skript na podepsani adresare se ZPMZ, zabeleni do ZIPu.
# Parametrem je jmeno slozky se ZPMZ.
# Vyuziva nastroje 7zip, GAWK, OpenSSL a sha512sum
#
# Historie:
#  2019_08_19  Druha verze, ktera se objede bez KDirSign programu
#

#
# Definice promennych
#
JAVA_PRG=java
GAWK_PRG=awk
ZIP_PRG=7za
OPENSSL_PRG=openssl
SHASUM_PRG=sha512sum
CURL_PRG=curl
KDIRVERIFY_OUTPUT_FILE=/tmp/KDirVerifyResult.html

IGNORE_FILES="Overeni_UOZI.txt"    # Pattern pro grep pri filtrovani souboru nalezenych ve vstupnim adresari. Standardne je treba vyloucit pripadne vysledky z predchoziho behu skriptu:
#Overeni_UOZI.txt
#Overeni_UOZI.txt.p7s
#Overeni_UOZI.txt.p7s.tsr

CERT_FILE="/home/votocek/Data_aplikaci/GP/Certifikaty/2019-Votocek.pem"
SIGNER_FILE="/home/votocek/Data_aplikaci/GP/Certifikaty/2019-Votocek.key"

# Definice pro komunikaci s vydavatelem casovych razitek (pouzita v tomto pripade autorita PostSignum)
# 1. Demo TSA - pro testovani
TSA_URL="https://www3.postsignum.cz/DEMOTSA/TSS_user/"
TSA_CRED="demoTSA:demoTSA2010"
# 2. Produkcni TSA - potreba mit zakaznicky ucet a dopredu nakoupeny balicek casovych razitek
TSA_URL="https://www.postsignum.cz/TSS/TSS_user/"
TSA_CRED="<e-mailova adresa>:<heslo pro prihlaseni do zakaznickeho portalu>"

#
# Definice pomocnych funkci
#
function coloredEcho(){
    local exp=$1;
    local color=$2;
    if ! [[ $color =~ '^[0-9]$' ]] ; then
       case $(echo $color | tr '[:upper:]' '[:lower:]') in
        black) color=0 ;;
        red) color=1 ;;
        green) color=2 ;;
        yellow) color=3 ;;
        blue) color=4 ;;
        magenta) color=5 ;;
        cyan) color=6 ;;
        white|*) color=7 ;; # white or invalid color
       esac
    fi
    tput setaf $color;
    tput bold
    echo $exp;
    tput sgr0;
}


function usage {
echo
coloredEcho "Davkovy program pro zpracovani slozky se ZPMZ (tez poklady mereni)." yellow
coloredEcho "Verze 2 bez pouziti KDirSign programu." white
coloredEcho "Program provadi nasledujici cinnosti:" yellow
echo "1) Vytvori protokol o overeni ve slozce ZPMZ a opatri ho externim elektronickym"
echo "podpisem vcetne casoveho razitka."
echo "2) Zkomprimuje (=zabali) do archivu ZIP soubory ve slozce ZPMZ"
echo "3) Pripravi text emailu pro zaslani na podatelnu katrastralni pracoviste."
echo
echo "Program je potreba spustit s parametrem. Tim je cesta ke slozce ZPMZ."
echo "Tedy napriklad:"
coloredEcho "  Davkove_podepsani_ZPMZ.sh \"/home/votocek/GP/Steti/Steti_I_1580/ZPMZ\"" cyan
echo
echo "Idealni je zadat parametr pretazenim slozky na ikonu s timto programem."
echo
return;
}


#
# Hlavni telo programu
#
# Prvni a jedinny parametr programu je cesta do adresare se ZPMZ
VSTUP=$1
echo -n "Zadana slozka pro podepsani: "
coloredEcho "$VSTUP" yellow


if [ -z "$VSTUP" ]; then   # Vstupni parametr je prazdny
  usage

# Poznamky k parametrum funkce read:
# -r specifies raw mode, which don't allow combined characters like "\" or "^".
# -s specifies silent mode, and because we don't need keyboard output.
# -p $'prompt' specifies the prompt, which need to be between $' and ' to let spaces and escaped characters. Be careful, you must put between single quotes with dollars symbol to benefit escaped characters, otherwise you can use simple quotes.
# -n1 specifies that it only needs a single character.
# key serve in case you need to know the input, in -n1 case, the key that has been pressed.
# $? serve to know the exit code of the last program, for read, 142 in case of timeout, 0 correct input. Put $? in a variable
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 1
fi

# Test existence adresare zadaneho parametrem
if [ ! -d "$VSTUP" ]; then
  coloredEcho "CHYBA: Byla zadana neexistujici slozka $VSTUP" red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 2
fi

#
# Zjisteni informaci zapisovanych do textoveho protokolu
#
echo
coloredEcho "Zadani cisla overeni ZPMZ" blue
read -r -p "Zadejte cislo overeni ve formatu cislo/rok a stisknete enter: " CISLO_OVERENI
#echo ${CISLO_OVERENI}

# Datum, ktery zapiseme do textoveho protokolu
DATUM_PODPISU=$(date "+%d.%m.%Y")


#
# Vytvor hlavicku textoveho souboru Overeni_UOZI.txt
#
OUTTXT="$VSTUP/Overeni_UOZI.txt"
echo
coloredEcho "Vytvarim obsah souboru Overeni_UOZI.txt" blue
echo "Náležitostmi a přesností odpovídá právním předpisům." > ${OUTTXT}
echo "${CISLO_OVERENI}" >> ${OUTTXT}
echo ${DATUM_PODPISU} >> ${OUTTXT}
echo "Ing. Aleš Votoček" >> ${OUTTXT}
echo "----" >> ${OUTTXT}

#
# Pridani seznamu souboru a jejich hashu pomoci SHA512
#
# Format radky je:
# <nazev souboru>;<hash>
# 763691_ZPMZ_01580_nacrt.pdf;64a9ebf333d2e400ac....
HASH=""                    # Hash konkretniho zpracovavaneho souboru
declare -a ZPMZ_SOUBORY    # Pole se jmeny souboru zahrnutych pro nasledne podepsani. Pole se pouzije jen pro vypis na obrazovku pred potvrzenim uzivatele.
POCET_ZPMZ_SOUBORU=0       # Citac poctu souboru
for f in $(ls -1 "${VSTUP}")
do
  #echo "DEBUG: >>>${f}<<<"
  if [ "$(echo "${f}" | grep -i "${IGNORE_FILES}")" == "" ]; then
    ((POCET_ZPMZ_SOUBORU++))
    ZPMZ_SOUBORY[POCET_ZPMZ_SOUBORU]=${f}

    # Vypocet SHA512 hashe pro dany soubor.
    # POZOR: KDirSign a zejmena KDirVerify pracuji s velkymi pismeny (=cislicemi 16-kove soustavy) --> vystup z sha512sum musim zkonvertovat z malych na velke
    HASH=$(${SHASUM_PRG}  "${VSTUP}/${f}" | $GAWK_PRG "{print \$1}" | tr [:lower:] [:upper:])
    echo "${f};${HASH}" >> ${OUTTXT}
    HASH=""
  else
    echo "INFO: Preskakuji pri zpracovani soubor ${f} ..."
  fi
done

echo
coloredEcho "Rekapitulace zadani" blue
echo -n "Zadano cislo overeni: "
coloredEcho ${CISLO_OVERENI} yellow
echo -n "Datum overeni: "
coloredEcho ${DATUM_PODPISU} yellow
echo -n "Pocet zpracovanych souboru v adresari ZPMZ: "
coloredEcho ${POCET_ZPMZ_SOUBORU} yellow
echo "Zpracovane soubory ZPMZ:"
for ((i=1;i<=${POCET_ZPMZ_SOUBORU};i++)); do
  coloredEcho ${ZPMZ_SOUBORY[$i]} yellow
done

echo
echo "Pokud udaje vyse nejsou spravne, ukoncete program a spustte program znovu."
coloredEcho "Chcete pokracovat podepsanim ZPMZ? [a] nebo ukoncit program [n] ?" white
    while true; do
      read -n1 -r -p "Pokracovat (a/n)? " key
      case $key in
          [Aa]* ) break;;
          [Nn]* ) echo;
                  echo "Koncim program.";
                  exit 3 ;;
          * ) echo "  Prosim odpovezte stisknutim klaves 'a' nebo 'n'! ";;
      esac
    done
    echo

#
# Podepsani Overeni_UOZI.txt
#
coloredEcho "Podepisuji ZPMZ ..." blue
${OPENSSL_PRG} smime -sign -binary -in "${OUTTXT}" -signer "${CERT_FILE}" -inkey "${SIGNER_FILE}" -outform DER -out "${OUTTXT}.p7s"
CHYBA=$?
if [ $CHYBA -gt 0 ]; then
  coloredEcho "CHYBA: Nastala chyba pri vytvareni elektronickohe podpisu slozky ZPMZ." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 3
fi
if [ ! -e "${OUTTXT}.p7s" ]; then
  coloredEcho "CHYBA: Soubor ${OUTTXT}.p7s nebyl vytvoren." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 4
fi
coloredEcho "OK, podepsano." green
echo



#
# Opatreni souboru podpisu (Overeni_UOZI.txt.p7s) casovym razitkem
#
# V prvni fazi vytvorim zadost o casove razitko
coloredEcho "Prikladam casove razitko - faze 1 - zadost" blue
${OPENSSL_PRG} ts -query -data "${OUTTXT}.p7s" -cert -sha256 -out "${OUTTXT}.tsq"
CHYBA=$?
if [ $CHYBA -gt 0 ]; then
  coloredEcho "CHYBA: Nastala chyba pri vytvareni zadosti o casove razitko." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 5
fi


# V druhe fazi odeslu zadost na autoritu poskytujici casova razitka
coloredEcho "Prikladam casove razitko - faze 2 - spojeni s autoritou" blue
${CURL_PRG} -k -u "${TSA_CRED}" -H "Content-Type: application/timestamp-query" --data-binary @"${OUTTXT}.tsq" -X POST "${TSA_URL}"  > "${OUTTXT}.p7s.tsr"
CHYBA=$?
if [ $CHYBA -gt 0 ]; then
  coloredEcho "CHYBA: Nastala chyba pri komunikaci s certifikacni autoritou." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 6
fi
if [ ! -s "${OUTTXT}.p7s.tsr" ]; then
  coloredEcho "CHYBA: Soubor ${OUTTXT}.p7s.tsr nebyl vytvoren nebo je prazdny." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 7
fi
coloredEcho "OK, orazitkovano." green
echo


# Smazeme zadost o casove razitko, neni dale potreba.
rm "${OUTTXT}.tsq" 2> /dev/null


# Odstranim ze zdrojove cesty posledni adresar. Bude se to hodit:
# a) jako cil pro vytvoreni ZIP archivu se ZPMZ
# b) jako cil pro vytvoreni textu s mailovou zpravou
#
# AWK Program - Linux version (lisi se znaky lomitek v ceste a escapovanim znaku dolar):
#{
#  if (index($0,"/") > 0) {    # Hledame, zdali je v ceste vubec znak lomitko
#     print substr($0,1,match($0,/\/[^\/]+[\/]?$/))  # Pokud ano, pak posledni adresar z cesty odebereme
#  } else {   print "./"}      # Pokud neni (=zadali jsme jako vstup skriptu jmeno adresare nachazejici v aktualnim adresari), pak vratime aktualni adresar
#}
export VYSTUP_ADR=$( echo $VSTUP | $GAWK_PRG "{if (index(\$0,\"/\") > 0) {print substr(\$0,1,match(\$0,/\/[^\/]+[\/]?\$/)) } else {print \"./\"} }")

echo "Vystupni slozka pro nasledne akce: $VYSTUP_ADR"


# Volitelne: Pokud adresovara cesta obsahuje cislo ZPMZ a cislo katastralniho uzemi, je mozne je vyextrahovat a pouzit ke spravnemu pojmenovani ZIP archivu nize
# Zde pro jednoduchost preskoceno

#
# Komprimace slozky ZPMZ do ZIP archivu
#
echo
coloredEcho "Nyni provedu komprimaci (=zabaleni) slozky se ZPMZ ..." blue
ZIP_ARCHIV="${VYSTUP_ADR}ZPMZ_$$.zip"
# Varianta, pokud znam cislo ZPMZ a kod katastralniho uzemi:
#ZIP_ARCHIV="${VYSTUP_ADR}${KATUZE}_ZPMZ_${CISLOZPMZ}.zip"
$ZIP_PRG a -tzip "$ZIP_ARCHIV" "${VSTUP}/*"

CHYBA=$?

if [ $CHYBA -gt 0 ]; then
  coloredEcho "CHYBA: Nastala nejaka chyba pri komprimaci slozky ZPMZ - vyse." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 10
fi


if [ ! -f "$ZIP_ARCHIV" ]; then
  coloredEcho "CHYBA: Nenalezen ZIP archiv $ZIP_ARCHIV." red
  coloredEcho  "Je pravdepodobne, ze komprimaze slozky ZPMZ se nepovedla." red
  read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
  echo
  exit 11
fi


# Volitelne: Zmde muzete predgenerovat text e-mailu, kterym odeslate vysledky na katastralni urad.
# Zejmena se hodi, pokud znate cislo ZPMZ a kod katastralniho uzemi.
# Muzete pripravit oblibene fraze v e-mailu.
#
#SOUBOR_EMAIL="${VYSTUP_ADR}text_emailu.txt"


# Volitelne: Zavolani e-mailoveho programu (zde Thunderbird)
# Dotaz, zdali se pokusit vytvorit mailovou zpravu v thuderbirdu
# coloredEcho "Program se nyni muze pokusit sestavit e-mailovou zpravu v programu Thunderbird pro odeslani na KU." cyan
# while true; do
#     read -n1 -r -p "Chcete vytvorit e-mail (a/n)? " key
#     case $key in
#         [Aa]* ) echo;
#                 MAIL_PRILOHY="file://${ZIP_ARCHIV}"
#                 for f in `ls -1 "${VYSTUP_ADR}"${KATUZE}*${CISLOZPMZ}*_signed.pdf`
#                 do
# 				  MAIL_PRILOHY="${MAIL_PRILOHY},${f}"
#                 done
# 
# 				# Pouzijeme ve skriptu Odeslani_emailu.sh
# 				export MAIL_PRILOHY
# 				echo "K e-mailu budou prilozeny nasledujici soubory:"
# 				coloredEcho "$MAIL_PRILOHY" yellow
# 
#                 echo "Zkusime vytvorit nyni e-mailovou zpravu v programu Thunderbird ...";
# 				thunderbird -compose "to='kp.litomerice@cuzk.cz',subject='<ku> ${CISLOZPMZ}',attachment='${MAIL_PRILOHY}',body='$(cat ${SOUBOR_EMAIL})'"
#                 break;;
#         [Nn]* ) echo;
# 		        echo "Odpovedeli jste, ze nechcete vytvaret e-mail.";
# 				exit;;
#         * ) echo "  Prosim odpovezte stisknutim klaves 'a' nebo 'n'! ";;
#     esac
# done

echo "Konec programu."
read -n1 -r -p "Stisknete jakoukoliv klavesu pro pokracovani ..." key
