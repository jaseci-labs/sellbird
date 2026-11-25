import builtins;
import html;
import json;
import logging;
import re;
import unicodedata;
import from datetime { datetime, timezone }

glob logger = logging.getLogger("sellbird.handler"),
     KILL_SWITCH_KEY = "sending_paused",
     BOUNCE_COUNT_KEY = "bounce_count",
     MIN_SENDS_FOR_KILL_SWITCH = 10,
     INTENT_LABELS = set(
         "accepted_offer interested objection not_interested ooo wrong_person question unsubscribe escalate".split(),
     ),
     AUTO_REPLY_INTENTS = set("accepted_offer interested objection question wrong_person".split()),
     HANDOFF_KEY = "handoff:",
     NO_COMPANY_STOP_INTENTS = {"ooo", "wrong_person"},
     OPT_OUT_PATTERNS = tuple(
         ("unsubscribe|opt out|opt-out|remove me|take me off|stop emailing|stop contacting|stop sending|do not contact|do not email|don't contact|don't email|never contact|delete my info|delete my data").split(
             "|"
         ),
     ),
     NO_THANKS_RE = re.compile(
         r"(?<!\bor )\bno,?[ \t]+thank(?:s|[ \t]+you)\b(?![ \t]+(?:needed|necessary|required))"
     ),
     BARE_OPT_OUTS = set(
         ("stop|unsubscribe|remove|remove me|opt out|no thanks|no thank you|baja|no gracias|de baja|dar de baja|darme de baja|non merci|arret|arreter|desabonner|desabonnement|desabonnez-moi|desinscrire|desinscription|desinscrivez-moi|retirer|retirez-moi|הסר|הסירו|הסירי|תסיר|תסירו|להסיר|הסרה|להסרה").split(
             "|"
         ),
     ),
     _BARE_COURTESIES = set(
         "בבקשה נא תודה רבה por favor gracias saludos merci svp sil vous plait".split()
     ),
     _MOBILE_SIGNATURE_RE = re.compile(
         r"^[ \t\u200e\u200f]*(?:sent from my \w[^\n]*|get outlook for \w[^\n]*"
             r"|sent from \w+ mail[^\n]*|נשלח מ[^\n]*|קבל(?:ו)? את outlook[^\n]*"
             r"|enviado desde mi \w[^\n]*|obt[eé]n outlook para \w[^\n]*"
             r"|envoy[eé] de mon \w[^\n]*|obtenez outlook pour \w[^\n]*)$",
         re.IGNORECASE | re.MULTILINE,
     ),
     _HE_ME = r"(?:אותי|אותנו)",
     _HE_TO_ME = r"(?:אליי|אלי|אלינו|לי|לנו)",
     _HE_REMOVE = (r"(?:הסר|הסירו|הסירי|תסיר|תסירו|תסירי|להסיר|הורד|הורידו|הורידי|תוריד|תורידו"
         r"|תורידי|להוריד|מחק|מחקו|מחקי|תמחק|תמחקו|תמחקי|למחוק)"),
     _HE_TAKE_OUT = r"(?:הוצא|הוציאו|תוציא|תוציאו|תוציאי|להוציא|הסרה|להסרה|הורדה)",
     _HE_LIST = r"מ(?:ה)?(?:רשימ|תפוצ|דיוור|מאגר)\w*",
     _HE_CONTACT = r"ל(?:שלוח|פנות|כתוב|הטריד|התקשר|הציק)",
     _HE_NOT_INTERESTED = r"(?:לא|אינני|איני|איננו)\s+מעוני{1,2}(?:ן|נת|נים|נות)",
     HEBREW_OPT_OUT_PATTERNS = (
         _HE_REMOVE + r"\s+(?:(?:נא|בבקשה)\s+)?" + _HE_ME + r"(?!\s+ל\w)",
         _HE_REMOVE + r"\s+את\s+ה?(?:מייל|אימייל|כתובת|פרטים|מספר)\w*\s+(?:שלי|שלנו)",
         r"(?:"
             + _HE_REMOVE
             + "|"
             + _HE_TAKE_OUT
             + r")\s+(?:"
             + _HE_ME
             + r"\s+)?"
             + _HE_LIST
             + r"(?!\s+את(?!\w))",
         r"(?:אבקש|מבקש|מבקשת|מבקשים|מבקשות|בקשת|בקשה)\s+(?:ל)?הסרה(?!\s+(?:של|את)(?!\w))",
         r"(?:תפסיק|תפסיקו|תפסיקי|הפסק|הפסיקי)\s+(?:(?:כבר|בבקשה)\s+)?" + _HE_CONTACT,
         r"(?:הפסיקו|להפסיק)\s+(?:(?:כבר|בבקשה)\s+)?"
             + _HE_CONTACT
             + r"\s+(?:"
             + _HE_TO_ME
             + "|"
             + _HE_ME
             + ")",
         r"(?:נא|בבקשה)\s+להפסיק(?:\s+" + _HE_CONTACT + r"|(?=\s*(?:[.!]|$)))",
         r"אל\s+תפנ(?:ה|ו|י)\s+(?:אליי|אלי|אלינו)",
         r"(?:אל\s+(?:תכתוב|תכתבו|תכתבי)|(?:לא|אין)\s+לכתוב)\s+" + _HE_TO_ME,
         r"(?:אל\s+(?:תשלח|תשלחו|תשלחי)|(?:לא|אין)\s+לשלוח)\s+"
             + _HE_TO_ME
             + r"(?:\s+(?:עוד|יותר|שוב|מיילים|מייל|הודעות|דואר)|(?=\s*(?:[.!]|$)))",
         r"אל\s+(?:תטריד|תטרידו|תטרידי)\s+" + _HE_ME,
         r"(?:נא|בבקשה)\s+לא\s+להטריד",
         r"(?:אל\s+(?:תיצור|תיצרו|תיצרי|תצור|תצרו)|(?:לא|אין)\s+ליצור)\s+"
             r"(?:(?:איתי|איתנו|אתי|אתנו|עמי|עמנו)\s+)?קשר",
         r"(?:לא|אין)\s+לפנות\s+(?:אליי|אלי|אלינו|שוב)",
         r"(?:לא|אינני|איני|איננו)\s+(?:רוצה|רוצים|רוצות|מעוני{1,2}(?:ן|נת|נים|נות))\s+לקבל\s+"
             r"(?:(?:יותר|עוד|שוב)\s+)?(?:מיילים|מייל|אימיילים|הודעות|פניות|דיוור|דואר)",
     ),
     HEBREW_OPT_OUT_RE = re.compile(
         r"(?<!\w)[ובכלמשה]{0,2}(?:" + "|".join(HEBREW_OPT_OUT_PATTERNS) + r")(?!\w)"
     ),
     _HE_NOT_FINAL_BEFORE = set("אל לא אין אם ואם".split()),
     _HE_NOT_FINAL_AFTER_RE = re.compile(
         r"(?<!\w)(?:לפני|אחרי|עד|בשבת|בחג|בשישי|בוואטסאפ|וואטסאפ|בטלפון|בסמס|עדיף"
             r"|תתקשר|תתקשרו|תתקשרי|התקשר|התקשרו|התקשרי)(?!\w)",
     ),
     _HE_FOR_NOW = r"(?:\s+(?:כרגע|בינתיים|עכשיו|בזה|בכך))?",
     HEBREW_NO_THANKS_RE = re.compile(
         r"(?<!\w)(?<!או )(?<!למה )(?<!מדוע )(?<!אם )(?<!עדיין )(?<!עוד )(?:לא[ \t,]+|"
             + _HE_NOT_INTERESTED
             + _HE_FOR_NOW
             + r"[ \t,.!-]*)תודה(?!\w)"
                 r"|(?<!\w)תודה[ \t,.!-]+(?:(?:אבל|אך)[ \t]+)?(?:(?:אני|אנחנו|אנו)[ \t]+)?"
             + _HE_NOT_INTERESTED
             + _HE_FOR_NOW
             + r"(?=[ \t]*(?:[.!,]|$))",
     ),
     _ES_US = r"(?:me|nos)",
     _ES_LIST = (r"(?:(?:su|sus|la|las|el|los|esta|esa|este|ese|tu|vuestra)\s+)*"
         r"(?:lista|base|correo|mail|email|envio|registro|contacto|boletin)\w*"),
     _ES_MY_ADDRESS = r"(?:mi|mis|nuestro|nuestros)\s+(?:correo|mail|email|direccion|contacto|dato)\w*",
     _ES_MAIL = (r"(?:mas(?!\s+de\s)|correos?|mails?|emails?|e-mails?|mensajes?|publicidad|nada"
         r"|informacion|ofertas?)"),
     _ES_WRITE = r"(?:escribir|enviar|mandar|contactar|molestar)(?:me|nos|le|les)?",
     _ES_SAY_END = (r"(?=[ \t]*(?:[.!;]|$|,(?![ \t]*(?:pero|aunque|salvo|excepto|a[ \t]+menos|si)"
         r"(?!\w))))"),
     SPANISH_OPT_OUT_PATTERNS = (
         r"(?:darme|darnos|dame|danos|deme|denos|denme|dennos|me\s+den|me\s+de|nos\s+den)\s+de\s+baja",
         r"dar\s+de\s+baja\s+(?:mi|nuestro|nuestra|este|esta)\s+(?:correo|mail|email|direccion"
             r"|suscripcion|cuenta)",
         r"(?:saquen|saque|saca|quiten|quite|quita|borren|borre|borra|eliminen|elimine|elimina"
             r"|retiren|retire|retira)"
             + _ES_US
             + r"(?:\s+de\s+"
             + _ES_LIST
             + "|"
             + _ES_SAY_END
             + ")",
         r"(?:sacar|quitar|borrar|eliminar|retirar)" + _ES_US + r"\s+de\s+" + _ES_LIST,
         r"(?:saquen|quiten|borren|eliminen|retiren|remuevan|eliminar|borrar|retirar|remover|quitar)\s+"
             + _ES_MY_ADDRESS
             + r"\s+de\s+"
             + _ES_LIST,
         r"desuscrib\w+|desinscrib\w+|(?:cancelar|anular)\s+(?:mi\s+|la\s+)?suscripcion",
         r"no\s+" + _ES_US + r"\s+(?:escrib(?:a|as|an)|contact(?:e|es|en)|molest(?:e|es|en))(?!\w)",
         r"no\s+"
             + _ES_US
             + r"\s+(?:envi(?:e|es|en)|mand(?:e|es|en))(?!\w)(?:\s+"
             + _ES_MAIL
             + r"(?!\w)|"
             + _ES_SAY_END
             + ")",
         r"no\s+(?:" + _ES_US + r"\s+)?vuelva(?:s|n)?\s+a\s+" + _ES_WRITE,
         r"(?:dej|par)(?:e|en|a|ad)\s+de\s+" + _ES_WRITE,
         r"basta\s+de\s+(?:correos|mails|emails|mensajes|publicidad)",
         r"no\s+(?:quiero|queremos|deseo|deseamos)\s+(?:seguir\s+)?recibir\s+"
             r"(?:(?:mas|sus|estos|estas|ningun|ninguna)\s+)*"
             + _ES_MAIL,
         r"(?:no\s+"
             + _ES_US
             + r"\s+interesan?|no\s+(?:estoy|estamos)\s+interesad[oa]s?"
                 r"|no\s+(?:tengo|tenemos)\s+(?:ningun\s+)?interes)"
                 r"(?:\s+(?:por\s+ahora|por\s+el\s+momento|en\s+este\s+momento|ahora))?"
             + _ES_SAY_END,
     ),
     SPANISH_OPT_OUT_RE = re.compile(
         r"(?<!\w)(?:" + "|".join(SPANISH_OPT_OUT_PATTERNS) + r")(?!\w)", re.MULTILINE
     ),
     _ES_NOT_FINAL_BEFORE = set("no si porque cuando aun todavia como".split()),
     _ES_LAST_WORD_RE = re.compile(r"(\S+)[ \t]*\Z"),
     _ES_NOT_FINAL_AFTER_RE = re.compile(
         r"(?<!\w)(?:hasta|antes\s+de|despues\s+de|a\s+partir\s+de|mejor|whatsapp|por\s+telefono"
             r"|llam(?:e|a|en)(?:me|nos)|escrib(?:e|a|an|eme|ame|anme|enos|anos)(?:me|nos)?"
             r"|lunes|martes|miercoles|jueves|viernes|sabado|domingo|semana|mes|enero|febrero|marzo"
             r"|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?!\w)",
     ),
     SPANISH_NO_THANKS_RE = re.compile(
         r"(?<!\bo )(?<!como )(?<!si )(?<!que )(?<!porque )(?<!todavia )(?<!aun )"
             r"\bno,?[ \t]+(?:muchas[ \t]+)?gracias\b(?![ \t]+(?:a|por)\b)",
     ),
     _FR_US = r"(?:moi|nous)",
     _FR_ME = r"(?:m'|me\s+|nous\s+)",
     _FR_LIST = (r"(?:(?:votre|vos|la|les|le|cette|ce|ces|ta|tes|ton)\s+)*"
         r"(?:liste|base|envoi|registre|infolettre|bulletin|fichier|repertoire|contact|courriel"
         r"|distribution|diffusion)\w*"),
     _FR_MY_ADDRESS = (r"(?:mon|mes|notre|nos)\s+(?:adresse|courriel|nom|coordonnee|contact|donnee"
         r"|e-?mail)\w*"),
     _FR_MAIL = (r"(?:(?:de|des|vos|ces|tes|les|la|d')[ \t]*)*(?:courriels?|courriers?|mails?|e-?mails?"
         r"|messages?|publicites?|pubs?|offres?|infolettres?|sollicitations?|relances?|rien)"),
     _FR_WRITE = r"(?:ecrire|contacter|relancer|solliciter|deranger|importuner|harceler|texter)",
     _FR_SEND = r"(?:envoyer|transmettre|faire\s+parvenir)",
     _FR_SAY_END = (r"(?=[ \t]*(?:[.!;]|$|,(?![ \t]*(?:mais|sauf|a[ \t]+moins|si|par[ \t]+contre"
         r"|cependant|toutefois|quoique|bien[ \t]+que)(?!\w))))"),
     FRENCH_OPT_OUT_PATTERNS = (
         r"(?:desabonn|desinscriv)ez[- ]" + _FR_US + r"|(?:me|nous)\s+(?:desabonner|desinscrire)",
         r"(?:retirez|retire|enlevez|enleve|otez|ote|supprimez|supprime|rayez|raye|effacez|efface)[- ]"
             + _FR_US
             + r"(?:\s+(?:de|d')\s*"
             + _FR_LIST
             + "|"
             + _FR_SAY_END
             + ")",
         r"(?:me|nous)\s+(?:retirer|enlever|oter|supprimer|rayer|effacer)\s+(?:de|d')\s*"
             + _FR_LIST,
         r"(?:retirez|enlevez|supprimez|effacez|rayez|retirer|enlever|supprimer|effacer|rayer)\s+"
             + _FR_MY_ADDRESS
             + r"(?:\s+(?:de|d')\s*"
             + _FR_LIST
             + "|"
             + _FR_SAY_END
             + ")",
         r"n(?:e\s+|')"
             + r"(?:m'|me\s+|nous\s+)?"
             + r"(?:ecri(?:vez|s)|contacte[sz]?|relance[sz]?"
                 r"|sollicite[sz]?|derange[sz]?|importune[sz]?|harcele[sz]?)\s+(?:plus|pas|jamais)(?!\w)",
         r"n(?:e\s+|')"
             + r"(?:m'|me\s+|nous\s+)?"
             + r"(?:envoye[sz]|envoie[s]?|transmette[sz]?)" r"\s+(?:plus|pas|jamais)(?:\s+"
             + _FR_MAIL
             + r"(?!\w)|"
             + _FR_SAY_END
             + ")",
         r"ne\s+(?:plus|pas)\s+(?:jamais\s+)?" + _FR_ME + r"?" + _FR_WRITE,
         r"ne\s+(?:plus|pas)\s+(?:jamais\s+)?"
             + _FR_ME
             + r"?"
             + _FR_SEND
             + r"(?:\s+"
             + _FR_MAIL
             + r"(?!\w)|"
             + _FR_SAY_END
             + ")",
         r"(?:arrete[sz]?|arreter|cesse[sz]?|cesser)\s+(?:de\s+|d')"
             + r"(?:m'|me\s+|nous\s+)?"
             + _FR_WRITE,
         r"(?:arrete[sz]?|arreter|cesse[sz]?|cesser)\s+(?:de\s+|d')"
             + r"(?:m'|me\s+|nous\s+)?"
             + _FR_SEND
             + r"(?:\s+"
             + _FR_MAIL
             + r"(?!\w)|"
             + _FR_SAY_END
             + ")",
         r"(?:arrete[sz]?|cesse[sz]?|stoppe[sz]?)\s+(?:les|vos|ces|tes)\s+(?:courriels|envois|messages"
             r"|relances|sollicitations|mails|e-mails|emails)",
         r"(?:laissez|laisse)[- ]"
             + _FR_US
             + r"\s+tranquilles?|fou(?:tez|s)[- ]"
             + _FR_US
             + r"\s+la\s+paix",
         r"ne\s+(?:veux|voulons|veut|souhaite|souhaitons|desire|desirons)\s+(?:plus|pas)\s+"
             r"(?:rien\s+)?(?:recevoir(?:\s+"
             + _FR_MAIL
             + r"(?!\w)|"
             + _FR_SAY_END
             + r")|etre\s+(?:contacte|sollicite|relance)e?s?)",
         r"(?:(?:je\s+(?:ne\s+)?suis|nous\s+(?:ne\s+)?sommes|on\s+(?:n'|ne\s+)?est)\s+)?"
             r"pas\s+(?:du\s+tout\s+)?interess(?:e|ee|es|ees)"
             r"(?:\s+(?:pour\s+(?:le\s+moment|l'instant|maintenant)|en\s+ce\s+moment|merci))?"
             + _FR_SAY_END,
         r"(?:(?:ca|cela|ceci)\s+)?(?:ne\s+)?(?:m'|nous\s+)interesse(?:nt)?\s+pas(?:\s+du\s+tout)?"
             r"(?:\s+(?:pour\s+(?:le\s+moment|l'instant|maintenant)|en\s+ce\s+moment|merci))?"
             + _FR_SAY_END,
     ),
     FRENCH_OPT_OUT_RE = re.compile(
         r"(?<![\w'])(?:" + "|".join(FRENCH_OPT_OUT_PATTERNS) + r")(?![\w'])", re.MULTILINE
     ),
     _FR_NOT_FINAL_BEFORE = set(
         "ne n pas si pourquoi quand lorsque encore toujours vous tu il elle ils elles on etes es est sont serait seriez comme".split(),
     ),
     _FR_LAST_WORD_RE = re.compile(r"(\S+)[ \t]*\Z"),
     _FR_NOT_FINAL_AFTER_RE = re.compile(
         r"(?<!\w)(?:jusqu'|avant|apres|a\s+partir\s+d|plutot|mieux|whatsapp|texto|sms"
             r"|par\s+telephone|au\s+telephone|appel(?:ez|le)[- ](?:moi|nous)|telephonez"
             r"|ecri(?:vez|s)[- ](?:moi|nous)|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche"
             r"|semaine|mois|janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre"
             r"|novembre|decembre|automne|hiver|printemps|ete\s+prochain)(?!\w)",
     ),
     FRENCH_NO_THANKS_RE = re.compile(
         r"(?<!\bou )(?<!pourquoi )(?<!si )(?<!que )(?<!dire )"
             r"\bnon,?[ \t]+merci\b(?![ \t]*(?:a|pour|de|d'|bien)\b)",
     ),
     _INVISIBLE_RE = re.compile(
         r"[\u200e\u200f\u202a-\u202e\u2066-\u2069\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7]",
     ),
     OWN_TEXT_MIN_CHARS = 20,
     _LINK_ANNOTATION_RE = re.compile(r"<(?:mailto:|https?://)[^>\s]*>", re.IGNORECASE),
     _MERGE_TAG_RE = re.compile(r"\{\{\s*\w+\s*\}\}"),
     MODEL_OPT_OUT = {
         "rule": "model",
         "matched": "",
         "why": "No opt-out phrase matched; the model read the reply as a request to stop.",
     },
     ESCALATION_PATTERNS = tuple(
         ("lawyer|attorney|legal action|lawsuit|cease and desist|harassment|harassing|report you|reporting you|spam complaint|ftc|gdpr|can-spam|blacklist").split(
             "|"
         ),
     ),
     _HE_YOU = r"(?:אתכם|אותכם|אתכן|אותכן|אותך|אתך)",
     _HE_AGAINST_YOU = r"(?:נגדכם|נגדכן|נגדך)",
     _HE_ABOUT_YOU = r"(?:עליכם|עליכן|עלייך|עליך)",
     _HE_ACRONYM = r"[\"״'׳]{1,2}",
     _HE_NOT_INSURER = r"(?!\s+(?:ל|ב|מול\s+|אל\s+|דרך\s+)?ה?(?:ביטוח|חבר[הת]|קופ))",
     HEBREW_ESCALATION_PATTERNS = (
         r"(?:עורך|עורכת|עורכי|עורכות)\s+ה?דין",
         r"עו" + _HE_ACRONYM + "ד",
         r"עוה" + _HE_ACRONYM + "ד",
         r"יועמ" + _HE_ACRONYM + "ש",
         r"פרקליט\w*",
         r"(?:יועץ|יועצת|יועצי|יועצים|יועצות)\s+ה?משפטי(?:ת|ים|ות)?",
         r"מחלקה\s+ה?משפטית",
         r"(?:צעד|צעדים|הליך|הליכים|פעולה|פעולות|אמצעים)\s+משפטי(?:ים|ת|ות)?",
         r"(?:נקיטת|אנקוט|ננקוט|לנקוט)\s+(?:" + _HE_AGAINST_YOU + r"\s+)?ב?הליכים",
         r"ערכא(?:ה|ות)",
         r"(?:ניפגש|נפגש|נתראה)\s+ב?בית\s+ה?משפט",
         r"(?:אפנה|נפנה|אגיע|נגיע|אלך|נלך|אגרור|נגרור)\s+(?:" + _HE_YOU + r"\s+)?לבית\s+ה?משפט",
         r"תביעות\s+קטנות",
         r"(?:אתבע|נתבע|לתבוע|תובע|תובעת|תובעים|תובעות|תבעתי|תבענו)\s+" + _HE_YOU,
         r"אתבע(?:\s+(?:על|אם|את)(?!\w)|(?=\s*(?:[.!]|$)))",
         r"תביע(?:ה|ות)\s+(?:משפטית|משפטיות|ייצוגית|ייצוגיות)",
         r"(?:תביע(?:ה|ות)|תלונ(?:ה|ות))\s+(?:רשמית\s+)?(?:"
             + _HE_AGAINST_YOU
             + "|"
             + _HE_ABOUT_YOU
             + r"(?!\s+ל))",
         r"(?:" + _HE_AGAINST_YOU + "|" + _HE_ABOUT_YOU + r")\s+(?:תביעה|תלונה)",
         r"(?:אגיש|נגיש)\s+(?:תביעה|תלונה)" + _HE_NOT_INSURER,
         r"(?:תקבלו|תקבל|תקבלי)\s+(?:(?:ממני|מאיתנו|מאתנו)\s+)?תביעה",
         r"(?:צפו|תצפו|צפה|תצפה)\s+לתביעה",
         r"מכתב\s+ה?(?:התראה|דרישה)",
         r"התראה\s+(?:אחרונה\s+)?לפני\s+(?:נקיטת|תביעה|הליכים)",
         r"(?:אתלונן|נתלונן|להתלונן|התלוננתי|אדווח|נדווח|לדווח|דיווחתי|דיווחנו)\s+(?:"
             + _HE_AGAINST_YOU
             + "|"
             + _HE_ABOUT_YOU
             + ")",
         r"(?:תלונ(?:ה|ות)|אתלונן|נתלונן|להתלונן|התלוננתי)\s+(?:\S+\s+)?[בל]משטרה",
         r"(?:אלך|נלך|אפנה|נפנה|אגש|ניגש)\s+למשטרה",
         r"רשות\s+ל?הגנת\s+ה?(?:פרטיות|צרכן)",
         r"חוק\s+ה?(?:ספאם|תקשורת)",
         r"חוק\s+הגנת\s+ה?פרטיות",
         r"תיקון\s+(?:מס['׳.\"]?\s*)?40",
         r"סעיף\s+30\s*(?:א|a)",
         r"דברי?\s+ה?פרסומת",
         r"(?:ללא|בלי)\s+הוכחת\s+נזק",
         r"(?:תלונ(?:ה|ת|ות)|דיווח)\s+(?:על\s+)?ה?ספאם",
         r"(?:דיווחתי|דיווחנו|אדווח|נדווח|לדווח|סימנתי|אסמן|נסמן)\s+(?:\S+\s+){0,3}?כספאם",
         r"(?<!אם )(?<!לא )(?<!אין )(?:(?:זו|זאת|זה|זוהי)\s+(?:(?:ממש|פשוט|כבר)\s+)?"
             r"(?:(?:מהווה|מהוות)\s+)?|מדובר\s+ב)הטרד(?:ה|ות)",
         r"הטרד(?:ה|ות)\s+(?:מינית|מיניות|מאיימת|חוזרת|חוזרות)",
         r"(?:תלונ(?:ה|ות)|תביע(?:ה|ות)|בגין)\s+(?:על\s+)?ה?הטרד(?:ה|ות)",
         r"די\s+(?:עם\s+ה|ל)הטרד(?:ה|ות)",
         r"(?:אתם|אתה|אתן)\s+מטריד(?:ים|ות)?\s+(?:אותי|אותנו)",
         r"(?:תפסיק|תפסיקו|תפסיקי|הפסק|הפסיקו|הפסיקי)\s+להטריד",
         r"רשימ(?:ה|ות)\s+ה?שחור(?:ה|ות)",
         r"בלא?קליסט",
     ),
     HEBREW_ESCALATION_RE = re.compile(
         r"(?<!\w)[ובכלמשה]{0,2}(?:" + "|".join(HEBREW_ESCALATION_PATTERNS) + r")(?!\w)"
     ),
     HISTORY_BUDGET_CHARS = 24000,
     HISTORY_MESSAGE_CAP = 3000,
     HISTORY_LATEST_CAP = 12000,
     HISTORY_ALWAYS_RECENT = 6;

def _first_meant(regex: any, text: str, ends: str, after_re: any, held: any) -> any;
def _word_before(text: str, m: any) -> str;
def _he_held(text: str, m: any) -> bool;
def _es_held(text: str, m: any) -> bool;
def _fr_held(text: str, m: any) -> bool;
def _no_accents(text: str) -> str;
def _accent_free_lines(their_text: str) -> str;
def _flat(text: str) -> str;
def _opt_out_reason(their_text: str, own_words: str) -> dict[str, any] | None;
def _escalates(flat: str) -> bool;
def conversation_history(thread: any, prospect_name: str) -> str;

class OurText {
    has lines: set[str] = set(),
        joined: str = "";

    def init(texts: any);
    def _is_ours(line: str) -> bool;
    def remove(text: str) -> str;
}

class Handler {
    has brain: any = None,
        state: any = None,
        config: any = None,
        env: any = None,
        instantly: any = None,
        provider: any = None,
        secrets: any = None,
        _inbox_providers: dict[str, any] = {},
        skills: str = "",
        last_read_problem: str = "";

    def init(brain: any, state: any, config: any, env: any);

    @builtins.property
    def is_native -> bool;

    async def run -> bool;
    async def _handle_reply(reply: dict[str, any], campaign: any) -> bool;
    async def _our_text(prospect: any) -> OurText;
    async def _suppress(email: str, reason: str, source: str);
    async def _stop_colleagues(prospect: any);
    async def _escalation(email: str, reply_text: str, reason: str = "");
    async def _record_after_opt_out(
        prospect: any, reply_text: str, campaign_id: str = "", escalate: bool = False
    );
    async def _process_reply(
        lead_email: str,
        reply_text: str,
        reply_uuid: str,
        campaign_id: str = "",
        reply_meta: dict[str, any] | None = None,
    );
    async def _run_native -> bool;
    async def _read_inbox(provider: any, mailbox_id: str | None, label: str = "") -> bool;
    async def _handle_bounce(msg: any);
    async def _queue_native_reply(
        response: str, prospect: any, convo: any, reply_meta: dict[str, any], intent: str
    );
    def _instantly_reply_held(prospect: any, response: str) -> list[str];
    async def _think(prompt: str, task: str) -> any;
    async def _classify_intent(reply_text: str, prospect: any) -> str;
    def _determine_stage(intent: str, current_stage: str, reply_text: str) -> str;
    async def _hand_off_once(prospect: any, reply_text: str) -> any;
    async def _generate_response(
        intent: str, reply_text: str, prospect: any, convo: any, handoff: any = None
    ) -> str;
    async def _keep_to_rules(body: str, prospect: any) -> str;
}
