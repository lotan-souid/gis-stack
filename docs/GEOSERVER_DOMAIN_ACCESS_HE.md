# גישה ל־GeoServer דרך Caddy ו־Cloudflare Tunnel

תאריך התצפיות: 23 באוקטובר 2026 · גרסת GeoServer בפריסה שנבדקה: `3.0.2`.

מדריך זה מתעד את ממצאי המפעיל מהפריסה ואת ההגדרות הנדרשות לגישה דרך הדומיין. במסגרת כתיבת התיעוד לא בוצעה בדיקה חוזרת של השרתים ולא הוחלו עליהם שינויים. הפקודות להלן הן הוראות למפעיל; פעולת יצירת קונטיינר מחדש מסומנת בנפרד מבדיקות הקריאה.

## הסביבה ומסלולי הגישה

| רכיב | כתובת ותפקיד |
| --- | --- |
| `lxc-docker-02` | `192.168.0.135`, מריץ את `gis-stack` ב־Docker Compose |
| GeoServer | image מסוג `docker.osgeo.org/geoserver`, גרסה `3.0.2`; פורט מארח `8090` אל פורט קונטיינר `8080` |
| `lxc-caddy-01` | `192.168.0.101`, מריץ Caddy עם `tls internal` |
| הדומיין | `geoserver.lion2024.work`; ברשת הביתית `*.lion2024.work` מצביע ל־Caddy |
| גישה חיצונית | Cloudflare Access ו־Cloudflare Tunnel אל Caddy |

```text
ברשת הביתית: דפדפן → HTTPS אל Caddy → HTTP אל 192.168.0.135:8090 → GeoServer:8080
מחוץ לרשת: דפדפן → Cloudflare Access / Tunnel → HTTPS אל Caddy → אותו upstream
```

הכתובות הן דוגמאות מהפריסה שנמסרה, ואינן ערכים שנקראו מ־`.env`. ה־CA הפנימי של Caddy מנפיק את התעודה ברשת הביתית; לקוח מקומי צריך לתת בו אמון כדי לאמת אותה.

ב־[`docker-compose.yml`](../docker-compose.yml) השירות נקרא `geoserver`, ה־image משתמש ב־`${GEOSERVER_VERSION}`, ומיפוי הפורט הוא `${BIND_ADDR:-0.0.0.0}:${GEOSERVER_PORT}:8080`. ב־[`.env.example`](../.env.example) מוגדרים `GEOSERVER_VERSION=3.0.2` ו־`GEOSERVER_PORT=8090`. כתובות המארחים, Caddy ו־Cloudflare מנוהלים מחוץ לריפו. שינוי הדוגמה אינו מעדכן אוטומטית `.env`, משתני Portainer או קונטיינר קיים. [פרסום GeoServer 3.0.2](https://geoserver.org/announcements/vulnerability/2026/10/19/geoserver-3-0-2-released.html).

## Cloudflare Tunnel: HTTPS, SNI ו־Host

ב־Public hostname של `geoserver.lion2024.work` נבדקו ההגדרות הבאות:

| הגדרה | ערך בפריסה |
| --- | --- |
| Service URL | `https://192.168.0.101` |
| Match SNI to host | מופעל |
| Disable TLS certificate verification | מופעל, משום שהתעודה של Caddy חתומה ב־CA פנימי |
| HTTP Host Header | `geoserver.lion2024.work` |

אין להשתמש כאן ב־`http://192.168.0.101`: שם האתר ב־Caddyfile מוגדר בלי קידומת `http://`, ולכן Caddy מחזיר בפורט 80 הפניית `308` ל־HTTPS. הדפדפן חוזר ל־Cloudflare, המנהרה פונה שוב ל־HTTP ונוצרת לולאת הפניות.

SNI מזהה את שם האתר בשלב חיבור ה־TLS ומאפשר ל־Caddy לבחור תעודה; בלי ההגדרה הזו חיבור ה־TLS נכשל בפריסה שנבדקה. כותרת HTTP Host Header מזהה את האתר בבקשת HTTP עצמה. ביטול אימות התעודה הוא מצב הפריסה המתועד, ומשמעותו שהמנהרה אינה מאמתת את תעודת ה־origin. [הגדרות origin של Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/origin-parameters/).

## משתני הסביבה של GeoServer

דוגמה לערכים ב־`.env`, לפי מסלול Caddy שתואר לעיל:

```dotenv
GEOSERVER_TRUSTED_PROXIES=192.168.0.101
GEOSERVER_CSRF_WHITELIST=geoserver.lion2024.work
```

שני המשתנים כבר מועברים בשירות `geoserver`, תחת `environment:`:

```yaml
      GEOSERVER_TRUSTED_PROXIES: "${GEOSERVER_TRUSTED_PROXIES:-}"
      GEOSERVER_CSRF_WHITELIST: "${GEOSERVER_CSRF_WHITELIST:-}"
```

עצם הגדרת משתנה ב־`.env` אינה מוסיפה אותו לסביבת הקונטיינר: בקובץ הנוכחי ההעברה נעשית במפורש דרך `environment:`. שני המשתנים מקבלים ברירת מחדל ריקה ב־Compose. ה־whitelist מכיל את שם המארח עבור בדיקת CSRF; הוא אינו מחליף הגדרת Proxy Base URL.

`GEOSERVER_TRUSTED_PROXIES` מגדיר כתובות IP או טווחי CIDR של proxies מהימנים, מופרדים בפסיק. ב־GeoServer 3, ללא הוספת Caddy לרשימה, נצפתה ההודעה:

```text
Ignoring X-Forwarded-For from 192.168.0.101, not a trusted proxy
```

ההודעה מתייחסת ל־`X-Forwarded-For`; אין להסיק ממנה לבדה שכל כותרות `X-Forwarded-*` נדחות באותו מנגנון. אם המנהרה תגיע ישירות ל־GeoServer במקום דרך Caddy, יש להוסיף לרשימה גם את כתובת המקור שלה כפי ש־GeoServer רואה אותה. [הגדרת trusted proxies של GeoServer](https://docs.geoserver.org/main/en/user/configuration/properties/).

**החלת שינוי בידי המפעיל — משנה את הקונטיינר:** אחרי שינוי משתני הסביבה מריצים מתוך תיקיית ה־stack:

```bash
docker compose up -d geoserver
```

Compose יוצר מחדש את הקונטיינר כשהתצורה השתנתה. `docker compose restart geoserver` אינו טוען ערכי סביבה חדשים. לפני הפעלה מחדש יש להביא בחשבון את איפוס המשתמשים המתואר בסעיף הבא.

**בדיקת קריאה בלבד:** הצגת שני המשתנים ללא הדפסת סביבת הקונטיינר כולה או סודות:

```bash
docker compose exec -T geoserver printenv GEOSERVER_TRUSTED_PROXIES GEOSERVER_CSRF_WHITELIST
```

הפקודה משתמשת בשם השירות ואינה תלויה בשם קונטיינר כמו `gis-stack-geoserver-1`. [העברת משתני סביבה ב־Compose](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) ו־[התנהגות restart](https://docs.docker.com/reference/cli/docker/compose/restart/).

## איפוס משתמש המנהל וקובצי המשתמשים בהפעלה

בפריסה שנבדקה, כאשר `GEOSERVER_ADMIN_USER` ו־`GEOSERVER_ADMIN_PASSWORD` מוגדרים, סקריפט ההפעלה מחליף את `security/usergroup/default/users.xml` ואת `security/role/default/roles.xml` בתבניות המקור, עם פרטי המנהל שמתקבלים מסביבת הקונטיינר. בלוג נצפו `USING USERS XML ORIGINAL` ו־`Successfully replaced`. [סקריפט עדכון פרטי הגישה של ה־image הרשמי](https://github.com/geoserver/docker/blob/master/update_credentials.sh).

המשמעות: שינוי סיסמה בממשק, וכן משתמשים ותפקידים שנוצרו ב־default user/role services דרך הממשק, נדרסים בהפעלה הבאה שמריצה את הסקריפט. פעולת `up` שמפעילה או יוצרת מחדש את הקונטיינר יכולה להפעיל אותו; `up` שאינו משנה קונטיינר שכבר רץ אינו כשלעצמו הפעלה מחדש.

**פתוח — מדיניות ניהול משתמשים:** האפשרות להסיר את שני משתני המנהל לאחר ההגדרה הראשונה דורשת החלטה ושינוי נפרד. ה־Compose הנוכחי מחייב `GEOSERVER_ADMIN_PASSWORD` באמצעות `${GEOSERVER_ADMIN_PASSWORD:?set GEOSERVER_ADMIN_PASSWORD}` ומעביר גם את שם המנהל. לכן מחיקתם מ־`.env` בלבד אינה נוהל ישים כרגע: בהיעדר מקור אחר לסיסמה, Compose יסרב לעלות. יש להחליט אם פרטי הגישה מנוהלים בסביבת הקונטיינר או במאגר המשתמשים המתמשך; מדריך זה אינו משנה את הבחירה.

לגבי `$` בסיסמאות: Compose מבצע אינטרפולציה בערכים לא מצוטטים או במירכאות כפולות ב־`.env`. `$$` הוא escape של Compose עבור סימן דולר מילולי; ערך בגרשיים יחידים ב־`.env` מטופל מילולית, ולכן אין להכפיל בו דולר אוטומטית. אין לשמור דוגמאות של סיסמאות אמיתיות בתיעוד או להדפיס `docker compose config` מלא עם סודות. [כללי `.env`](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) ו־[escaping של דולר ב־Compose](https://docs.docker.com/reference/compose-file/interpolation/).

## התחברות דרך הדומיין: Proxy Base URL ו־CSP

**התסמין שנצפה:** דרך `https://geoserver.lion2024.work/geoserver/web/` מתוך הרשת הביתית, ניסיון התחברות נכשל ללא הודעה בממשק. קונסול הדפדפן דיווח ש־CSP חוסם שליחת טופס אל `http://geoserver.lion2024.work/geoserver/j_spring_security_check`, עקב `form-action 'self'`.

GeoServer יצר action עם `http://`: שם המארח הגיע מכותרת `Host`, ואילו החיבור הפנימי מ־Caddy ל־GeoServer היה HTTP. הדף נטען ב־HTTPS, ולכן כתובת ה־action שונה ב־origin והדפדפן חוסם את השליחה. הוספת CSRF whitelist לבדה אינה מתקנת את כתובת הטופס.

**הגדרה בממשק, לביצוע בידי המפעיל:** ב־Settings › Global, להגדיר Proxy Base URL כך:

```text
${X-Forwarded-Proto}://${X-Forwarded-Host}/geoserver
```

לסמן **Use headers for Proxy URL** ולשמור. זו תבנית של GeoServer המבוססת על כותרות HTTP, ואינה שורת משתנה להדבקה ב־`.env`. [תיעוד Proxy Base URL ותבניות headers](https://docs.geoserver.org/main/en/user/configuration/globalsettings/). Caddy שולח כברירת מחדל את `X-Forwarded-Proto` ואת `X-Forwarded-Host`; במסלול HTTPS שתואר הם מתארים את הגישה החיצונית אל Caddy. [כותרות reverse proxy ב־Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#defaults).

אין לקבע כאן `https://geoserver.lion2024.work/geoserver` אם רוצים לשמור גם גישה ישירה דרך `http://192.168.0.135:8090`: כתובת קבועה תשלח גם טופס שנפתח לפי IP אל הדומיין, וה־CSP עלול לחסום אותו בגלל הבדל ב־origin.

**השערה — לא נבדק:** מחוץ לרשת ההתחברות עבדה עוד קודם, אולי בגלל Automatic HTTPS Rewrites של Cloudflare ששכתב קישורי HTTP ל־HTTPS. ההסבר לא אומת ואין להסתמך עליו כפתרון.

**לא נבדק:** בגישה ישירה לפי IP, ללא כותרות `X-Forwarded-*`, האם התבנית אינה חלה וכתובת הטופס וההתחברות נשארות תקינות. יש לבדוק זאת בנפרד; המדריך אינו מבטיח fallback תקין במסלול הזה.

### בדיקת הטופס מתוך הרשת הביתית

בדיקת קריאה ללא התחברות, שמפנה את הבקשה ישירות ל־Caddy ומשמרת cookies בקובץ זמני:

```bash
curl -sk -L -c /tmp/gs.txt -b /tmp/gs.txt --resolve geoserver.lion2024.work:443:192.168.0.101 \
  https://geoserver.lion2024.work/geoserver/web/ | grep -o '<form[^>]*j_spring_security_check[^>]*>'
```

ה־`action` בפלט צריך להתחיל ב־`https://geoserver.lion2024.work/`. האפשרות `-k` עוקפת אימות תעודה בבדיקת ה־CA הפנימי הזו. הפקודה בודקת את כתובת הטופס בלבד; היא אינה מוכיחה שהתחברות עם משתמש וסיסמה מצליחה. אם אין פלט, אין לראות בכך הצלחה.

## הקשר למפות ב־rb (Frappe)

המערכת `rb-new.lion2024.work` מציגה WMS דרך `/gis/` בדומיין שלה, ש־Caddy מעביר ישירות ל־`192.168.0.135:8090` עבור בקשות `GetMap` בפורמט תמונה לאחר בדיקת התחברות מול Frappe; הגדרת המסלול מתועדת בריפו `rb`, בקובץ `docs/architecture/gis-form-maps.md`.

זהו מסלול נפרד מהדומיין `geoserver.lion2024.work`: המנהרה שלו ופתרון ההתחברות לממשק GeoServer אינם נתיב הטעינה של המפה ב־rb. שינוי כתובת GeoServer, הפורט, ה־workspace `rb-gis-itm` או קבוצת השכבות `L2026-10-03_rb-gis-itm` כן מחייב עדכון של Caddy ושל טופס השכבה ב־rb. הפרדה זו אינה הבטחה ששינוי הרשאות הנתונים ב־GeoServer לא ישפיע על WMS.

## נקודות פתוחות ובדיקות שטרם הושלמו

| מצב | נושא |
| --- | --- |
| פתוח | בדיווח המפעיל, הדומיין נגיש ברשת הביתית ל־WFS ללא הזדהות, ו־`GetFeature` על `lots` מחזיר את כל השדות. ממתינים להחלטה אם צוות GIS יעבוד דרך WFS או ישירות מול PostGIS; אין כאן שינוי הרשאות. |
| פתוח | לפי הבדיקה שנמסרה, GeoServer בוחר שירות לפי הבקשה גם כשהנתיב מסתיים ב־`/wms`: הפרמטר `service=WFS` מחזיר WFS, ובמקרה `service=WMS&SERVICE=WFS` הערך השני גבר. כל הגבלה ב־proxy חייבת להתייחס גם לפרמטרים ולכפילויות, ולא להסתמך רק על הנתיב; אין להסיק שכל גרסה תבחר תמיד באותו ערך כפול. |
| פתוח | שכבות ההדגמה `spearfish`, `tasmania`, `ne:*`, `sf`, `tiger`, `nurc` עדיין טעונות לפי דיווח המפעיל; מומלץ להסירן במסגרת שינוי נפרד. |
| פתוח | אם בוצע לאחרונה שדרוג מ־2.x ל־3.0.2, להשלים סקירת שינויי התנהגות ותאימות, ובפרט CSP ו־trusted proxies. |
| פתוח | לבחור מדיניות לניהול משתמשים ותפקידים מול איפוס קובצי default בהפעלה ומשתנה סיסמת המנהל הנדרש ב־Compose. |
| לא נבדק | fallback של Proxy Base URL והתחברות לפי IP ללא כותרות forwarded. |
| השערה, לא נבדק | האם Automatic HTTPS Rewrites של Cloudflare מסביר מדוע ההתחברות מבחוץ עבדה לפני תיקון Proxy Base URL. |
