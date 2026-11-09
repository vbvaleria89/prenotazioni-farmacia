# Prenota in Farmacia (scheletro Flutter)

App Android + iOS per prenotare servizi in farmacia: **analisi tricologica, Holter, analisi varie**.

## Stack
- Flutter (una codebase → App Store + Play Store)
- Previsto: Firebase (Auth, Firestore, Cloud Functions) + Google Calendar API
- Ora: dati mock in memoria, `MockCalendarService`

## Vincoli
- **Stanza unica**: un solo appuntamento alla volta su TUTTI i servizi. `BookingService.isRoomFree` controlla sovrapposizioni globali (non per servizio) + intervalli occupati dal calendario (freebusy). Annullato/“Libera stanza” rilasciano l'orario.
- **Staff al banco**: una sola schermata “Oggi”, orari grandi, bottoni Conferma / Annulla / Libera stanza a un tap.

## Avvio
```bash
flutter pub get
flutter run        # serve un emulatore/dispositivo Android o (su macOS) iOS
```

## Struttura
```
lib/main.dart, app.dart
lib/models/       service_type, appointment, user_role
lib/services/     booking_service (stanza unica), calendar_service (interfaccia + mock)
lib/screens/role_picker.dart
lib/screens/client/  services_home → slot_picker → booking_confirm
lib/screens/staff/   staff_today
```

## Prossimi passi
1. Firebase: Auth (clienti con telefono/email, staff con ruolo via custom claims), Firestore per appuntamenti.
2. Prenotazione **lato server** (Cloud Function con transazione) per evitare doppie prenotazioni concorrenti sulla stanza.
3. Google Calendar: un solo calendario “Stanza servizi” con service account; `createEvent`/`deleteEvent` + freebusy. Nel calendario solo servizio + orario + codice (niente dati sanitari, GDPR).
4. Orari apertura/chiusure configurabili dallo staff, notifiche push di promemoria.
5. Icone, bundle id definitivo, account sviluppatore Apple/Google per la pubblicazione.

## Identità brand – Farmacia San Ciro
- Nome: **Farmacia San Ciro** (dott.ri Guerra, Bagnoli) · motto «Il nostro scopo è il tuo benessere»
- Contatti: Via Giacinto de Sivo 1, 80124 Napoli · 081 570 4733
- Colori: primario navy `#32448C` (dal logo), accento verde farmacia `#2E9E4F`
- Logo: `assets/brand/logo_profile_200.jpg` (da pagina Facebook ufficiale)
- Tutto centralizzato in `lib/theme/brand.dart` (`Brand`, `Brand.theme()`, `BrandAppBar`).

## Google Calendar (anteprima web)
- Calendario unico **"Stanza servizi - Farmacia San Ciro"** (stanza unica: ogni evento, anche creato a mano, blocca gli slot via freeBusy).
- Bridge JS `web/gcal.js` (Google Identity Services, token client, scope `calendar`) + `lib/services/google_calendar_service.dart`.
- Solo **client_id** è nel web (pubblico per natura). Il secret resta in `secrets/` (non copiato in `build/web`, non serve al flusso GIS).
- **Collegare:** area *Personale* → «Collega Google Calendar» → accedi con l'account Google della farmacia → stato «Google Calendar collegato».
- Eventi: titolo = servizio + codice prenotazione; niente nome/telefono/dati sanitari.
- Non collegato → fallback mock (banner arancione per lo staff).
- Limiti: token valido ~1h e solo nella sessione del browser (sessionStorage); i clienti su altri dispositivi NON scrivono sul calendario finché non c'è un backend (Cloud Function + service account). App OAuth in modalità "Testing": solo utenti di test autorizzati.

## Regole prodotto
- Stanza unica per tutti i servizi · NO Otopharma (ha la sua app)
- Tricologico: giorni fissi (`tricologicoDays`, placeholder) + sempre la stessa persona → TODO backoffice admin
- Altri servizi: chiunque sia di turno · TODO login per dipendente (chi ha gestito la prenotazione)

## Firebase (test dal vivo) — piano Spark

Progetto: `farmacia-san-ciro-prenota` (Auth Email/Password + Firestore europe-west1). Config web in `lib/firebase_options.dart`.

### Collezioni Firestore
- `employees/{uid}` — `email`, `nome`, `ruolo` (`admin|staff|tricologo`), `attivo` (uid = UID Firebase Auth)
- `settings/pharmacy` — `openHour`, `closeHour`, `tricologicoDays` (1=lun…7=dom), `tricologoEmployeeId`, `tricologoNome`, `serviziNote`
- `appointments/{id}` — `servizio`, `start`, `end`, `clienteNome`, `clienteTel`, `status` (`inAttesa|confermato|annullato|completato`), `createdBy`, `calendarEventId?`, `employeeId?`, `createdAt`
- `roomDays/{yyyy-m-d}` — lock tecnico per la transazione della stanza unica

### Flussi
- **Cliente**: nessun login visibile (sessione Firebase *anonima*), sceglie servizio/slot; slot = orari settings − appuntamenti attivi (stanza unica); tricologico solo nei giorni configurati.
- **Cliente**: prenota senza account, oppure entra in **Area personale** (email e password temporanea) e vede solo le sue prenotazioni. Il codice fiscale è obbligatorio.
- **Personale**: icona staff → email/password → appuntamenti di oggi in tempo reale; Conferma / Annulla / Libera stanza scrivono su Firestore.
- **Backoffice** (solo `ruolo: admin`): orari, giorni tricologico, persona tricologico, note servizi, elenco dipendenti.

### Seed
Admin creato una tantum via REST Identity Toolkit (signUp) + documenti `employees/<uid>` e `settings/pharmacy`.
Credenziali: `secrets/seed_users.txt` (fuori da `build/web`, non committare).
Nuovo dipendente: Console → Authentication → Aggiungi utente, poi Firestore → `employees/<UID>` con i campi sopra.

### Azioni manuali richieste (Console Firebase)
1. **Authentication → Metodo di accesso → Anonimo → Abilita** (senza, i clienti vedono "Prenotazione online non ancora attiva").
2. Pubblicare `firestore.rules` (regole per ruolo) al posto di "auth required".

### Google Calendar
Sync solo **lato browser dello staff**: se nella sessione staff è premuto "Collega Google Calendar", Conferma crea l'evento mancante e Annulla lo cancella; gli eventi esistenti nel calendario bloccano gli slot solo in quella sessione.
Le prenotazioni dei clienti vengono salvate su Firestore ma l'evento compare in Calendar solo quando lo staff collegato le conferma.
**Calendar server-side** (evento immediato + freebusy per i clienti) richiede Cloud Functions → piano **Blaze** (pochi €/mese), service account con accesso al calendario "Stanza servizi", function `onCreate(appointments)` + function `busy`.

### Limiti Spark
Niente Cloud Functions Firebase. Ricevuta e account cliente passano dalla Netlify Function `send-confirmation` con Firebase Admin SDK. 50k letture / 20k scritture / giorno su Firestore: ampiamente sufficienti per i test.

### Deploy
Dalla **root del repo** (così Netlify pubblica il web e aggiorna `netlify/functions`; un drag-and-drop della sola `build/web` non porta la function):

```bash
flutter build web --release
npm install
npx netlify-cli@17 deploy --dir=build/web --prod
```

Le variabili sotto vanno impostate sul sito **prima** del deploy che deve creare gli account. Senza di esse la prenotazione a schermo resta valida.

## Ricevuta email e account cliente

Nel form **cliente** l'email è facoltativa. Sopra il campo: «Per ricevere la ricevuta inserisci l'email». Senza email non si chiama la function e non si crea nessun account.

Con email, **dopo** `book()`, l'app fa `POST /.netlify/functions/send-confirmation`. Lo stesso endpoint vale per lo staff (`fromStaff`): lì l'email resta obbligatoria.

La function:

1. spedisce la ricevuta con Resend;
2. se c'è `FIREBASE_SERVICE_ACCOUNT` (o i tre pezzi) e la prenotazione esiste con la stessa `clienteEmail` e il codice coincide con i primi 6 caratteri dell'id, crea l'utente Auth email/password **solo se manca**, con password temporanea generata al momento;
3. se l'utente c'è già, non crea un doppione, scrive `clienteUid` / `clienteAccount` sulla prenotazione e nella mail mette le istruzioni (link per reimpostare la password, se non è un dipendente);
4. se l'email è di uno staff (`employees/{uid}`), non genera password e non manda il link di reset;
5. se account o mail falliscono, risponde un errore HTTP ma **il client mostra comunque la prenotazione confermata**.

La password non torna nel JSON, non va nei log e non è mai il codice fiscale. Un account senza documento `employees` è un cliente: entra in Area personale, non nei pannelli staff.

### Variabili Netlify

| Variabile | Ruolo |
|---|---|
| `RESEND_API_KEY` | Obbligatoria per inviare. Mai in git. |
| `MAIL_FROM` | Opzionale. Default `Farmacia San Ciro <prenotazioni@farmaciasanciro.net>` |
| `MAIL_REPLY_TO` | Opzionale. Default `farmaciasanciro@gmail.com` |
| `FIREBASE_SERVICE_ACCOUNT` | JSON del service account (una riga) oppure lo stesso JSON in base64. |
| `FIREBASE_PROJECT_ID` | Alternativa al JSON, insieme ai due campi sotto. Valore atteso: `farmacia-san-ciro-prenota`. |
| `FIREBASE_CLIENT_EMAIL` | Email del service account. |
| `FIREBASE_PRIVATE_KEY` | Chiave privata. Gli a capo possono essere scritti come `\n`. |

Modello senza valori: `.env.example`.

Service account: Firebase Console del progetto **Farmacia San Ciro Prenota** → Impostazioni progetto → Account di servizio → Genera nuova chiave privata. Ruoli minimi: Firebase Authentication Admin e Cloud Datastore User. Auth Email/Password è già attivo: va lasciato attivo, altrimenti la creazione utente fallisce (la prenotazione no).

Se il JSON manca, la ricevuta parte lo stesso e la risposta ha `"account":"not_configured"`.

### Campi aggiunti su `appointments/{id}`

Scritti solo dall'Admin SDK (le regole vietano al client di impostarli in creazione): `clienteUid`, `clienteAccount` (`created` | `existing` | `staff`), `accountLinkedAt`, `receiptSentAt`.

Pubblicare anche `firestore.rules` (`npx -y firebase-tools@latest deploy --only firestore:rules`) **dopo** il deploy dell'app. La function non ne ha bisogno per scrivere: usa l'Admin SDK. Le regole nuove obbligano il codice fiscale in creazione e fanno leggere al cliente solo le proprie prenotazioni. Prima di pubblicarle, entra una volta nell'area staff: l'app copia i prossimi 21 giorni nei blocchi `roomDays` (orari senza dati personali), così gli slot restano giusti anche quando il cliente non può più leggere tutte le prenotazioni.

## Area personale e codice fiscale

- In home il pulsante navy **Area personale** è l'ingresso cliente. Se sei già dentro, al suo posto c'è «Ciao, nome» (anche su orari e conferma), con tap verso le prenotazioni ed Esci. «Resta connesso» è attivo di default. L'icona in alto a destra è l'**area staff**.
- Lo staff entra in una griglia (Oggi, Calendario, Nuova prenotazione; l'admin ha anche Servizi, Assegnazioni e Bacheca). La bacheca (`notices`) la vede il cliente in Area personale, insieme al bottone WhatsApp. Nessun indice Firestore composto: gli attivi si ordinano nell'app.
- Un dipendente che entra da Area personale viene portato a Oggi. Un cliente che entra dall'area staff vede il messaggio e non apre i pannelli.
- Ogni prenotazione, anche senza email, richiede il codice fiscale (formato e carattere di controllo). È salvato in `appointments.clienteCodiceFiscale` e, se c'è un account, in `customers/{uid}`.
- La password dell'account resta quella temporanea casuale nella mail. In Area personale c'è il link per cambiarla.
- Senza email non si crea l'account: la prenotazione resta valida con il codice mostrato a schermo.

### Test automatici (niente rete, niente secret)

```bash
npm install
npm test
```

### Prova sul sito, dopo il deploy

Sito: https://farmacia-san-ciro-prenota.netlify.app

1. **Cliente senza email.** Prenota: compare il codice. In Firebase Authentication non nasce un utente. Non parte nessuna mail.
2. **Cliente con email nuova** (una casella tua). Prenota: il codice compare anche se la mail tarda o fallisce. In Authentication c'è l'utente. La mail ha ricevuta, email, password temporanea e link per cambiarla. Su Firestore `appointments/{id}.clienteUid` è valorizzato.
3. **Stessa email, altra prenotazione.** Nessun secondo utente. Mail con ricevuta e istruzioni / link di reset, senza una password nuova. La prenotazione è collegata.
4. **Email di un dipendente** presente in `employees/{uid}`. Mail senza password e senza link di reset. La password dello staff non cambia.
5. **Guasto.** Service account assente o `RESEND_API_KEY` errata: la prenotazione resta confermata. Lo staff, se l'invio non torna 200, vede il testo da copiare. Se l'account era già stato creato e la mail no, un secondo POST della stessa prenotazione non crea un doppione e manda il link per scegliere la password.
6. **Staff.** Email obbligatoria, stessa function.

Replay (manda una mail vera solo se la prenotazione esiste, `clienteEmail` coincide e Resend è attivo; usa un indirizzo tuo). Se id o email non coincidono la function risponde 409 e non spedisce. `codice` = primi 6 caratteri di `appointmentId` in maiuscolo.

```bash
curl -sS -X POST 'https://farmacia-san-ciro-prenota.netlify.app/.netlify/functions/send-confirmation' \
  -H 'content-type: application/json' \
  -d '{"to":"tu@example.com","nome":"Mario Rossi","codice":"ABCDEF","servizio":"Holter","quando":"04/11/2026 alle 10:00","appointmentId":"ABCDEF0123456789abcd"}'
```
