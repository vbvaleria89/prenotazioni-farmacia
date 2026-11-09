# Account e correzione contatti — v20

## Funzioni
- «Account» accanto a «Esci» nelle barre cliente, nell’area personale, nella pagina servizi e nello hub staff/admin.
- Cliente: nome, telefono, codice fiscale (con checksum); email di contatto in sola lettura.
- Staff/admin: nome; email e ruolo in sola lettura.
- Cambio password per tutti: password attuale, nuova password, conferma; Firebase reauthentication + updatePassword. Funziona anche per gli account `.local`, senza inviare email. Nessuna password persistita nei documenti.
- «Correggi dati cliente» in Oggi, Calendario ed Elenco: modifica nome, telefono ed email senza cambiare orario, stanza, stato o pagamento. Anche la modifica completa sincronizza i contatti.
- Prenotazione e profilo cliente esistente sono aggiornati nella stessa transazione. Collegamento per clienteUid; senza uid, ricerca univoca sull’email precedente (mai abbinamenti ambigui). Si propagano soltanto i contatti effettivamente modificati, senza sovrascrivere il CF o i dati più recenti non modificati.
- Il salvataggio account cliente conserva l’email di contatto corretta dal banco. Le nuove prenotazioni la precompilano dal profilo.
- La function ricevute conserva un clienteUid già collegato: correggere il recapito non crea un altro utente e non sposta le prenotazioni a un altro account. In questo caso non crea né invia credenziali o link di reset.

## Limiti intenzionali
- L’email Firebase Auth di accesso non cambia: la schermata account mostra separatamente l’email di accesso se diversa dal contatto. Un cambio identità richiede un flusso dedicato di verifica/Admin SDK.
- Nessun reinvio automatico delle ricevute già spedite; nessuna modifica massiva di altre prenotazioni storiche.
- Se manca il profilo Firestore o il collegamento email è ambiguo, viene corretta soltanto la prenotazione; non si inventano né si creano account.
- Il codice fiscale corretto dalla modifica completa resta sulla prenotazione: al banco si sincronizzano sul profilo solo nome, telefono ed email, secondo i permessi richiesti.

## Rules e verifiche
- Employees self-update: solo nome (stringa non vuota, meno di 100 caratteri), uid proprio, documento dipendente attivo; ruolo/email/attivo non modificabili dallo staff.
- Customers: personale attivo può aggiornare solo email/nome/telefono/updatedAt su documenti esistenti; tipi e limiti controllati, timestamp server obbligatorio, nessuna modifica a CF/password/identità. I permessi esistenti degli amministratori e dei clienti restano.
- Notifications: aggiunto aggiornamento limitato dell’anteprima per la modifica completa; readBy resta protetto. Nessuna creazione di notifiche incomplete.
- Validazione sintattica: `firebase deploy --only firestore:rules --dry-run`, superata.
- 33 test rules superati nell’emulatore Firestore, progetto demo isolato: salvataggi cliente/staff/admin, correzione atomica, altri uid negati, escalation ruolo/attivo negata, tipi/dimensioni/campi extra/timestamp falsi/cancellazione campi negati, letture anonime negate, anteprima notifiche consentita senza alterare readBy. Script e ambiente riproducibili sul box: `/workspace/farmacia-account-tests/`.
- Test Node ricevute e CF: 26 superati (inclusi due nuovi test di regressione contatto vs identità).
- I test Flutter preesistenti hanno due problemi estranei: widget_test importa dart:js_interop su VM non web; test WhatsApp attende uno zero che il codice esistente elimina. Non modificati per questa funzionalità.

### Audit circoscritto
```json
{
  "score": 3,
  "summary": "Le nuove autorizzazioni sono limitate e coperte da 33 test. Non è una certificazione delle regole preesistenti dell'intera applicazione.",
  "findings": [
    {"check":"Authority Source", "severity":"moderate", "issue":"Preesistente: isEmployee() verifica l'esistenza, non attivo, per diverse operazioni fuori dall'ambito account.", "recommendation":"Revisione separata dei privilegi dei dipendenti disattivati."},
    {"check":"Field-Level vs Identity-Level Security", "severity":"major", "issue":"Preesistente: roomDays permette lettura e scrittura a qualsiasi sessione autenticata, anche anonima, per la prenotazione pubblica.", "recommendation":"Hardening dedicato del protocollo di prenotazione e blocco stanze con vincoli sui singoli campi/transazioni."}
  ]
}
```

I've set up prototype Security Rules to keep the data in Firestore safe. They are designed to be secure for own-name updates and staff contact corrections through UID/role checks, bounded typed fields and immutable privilege fields. However, you should review and verify them before broadly sharing your app. If you'd like, I can help you harden these rules.

## Pubblicazione verificata
- Un solo deploy Vercel in produzione, stato READY: `dpl_Frdr2GbsD8BC4euACMmMKbZYZBMW`.
- URL: https://farmacia-san-ciro-prenota.vercel.app
- Rules Firestore pubblicate con successo sul progetto `farmacia-san-ciro-prenota`, database `(default)` STANDARD.
- Build web release riuscita; analisi dei 12 file/aree toccati senza problemi.
- Home live HTTP 200, tutte le stringhe build v20 aggiornate. SHA256 di `main.dart.js` e `flutter_bootstrap.js` live identici alla build locale.
- Log errori Vercel sul deployment appena pubblicato: nessun record nella finestra verificata.
- 26 test Node + 33 test rules + 4 test pagamento + test checksum CF superati. Non è stata eseguita una sessione interattiva di login con account reali né cambiata alcuna password reale.
