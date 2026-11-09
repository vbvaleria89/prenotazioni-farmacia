import {test} from 'node:test';
import assert from 'node:assert/strict';
import {provisionCustomerAccount, buildConfirmation} from './confirmation.mjs';

test('email di contatto corretta: conserva uid e non crea credenziali o link di reset', async()=>{
  let authTouched=false, storeTouched=false;
  const account=await provisionCustomerAccount({
    auth:new Proxy({}, {get(){authTouched=true;throw new Error('Non accedere ad Auth per un account già collegato')}}),
    store:{async getAppointment(){return {id:'abcdef123',clienteUid:'cliente-originale',clienteEmail:'corretta@example.test',clienteCodiceFiscale:'RSSMRA85T10A562S'}},async linkAppointment(){storeTouched=true},async saveCustomer(){storeTouched=true}},
    email:'corretta@example.test',appointmentId:'abcdef123',codice:'ABCDEF',
  });
  assert.equal(account.uid,'cliente-originale');
  assert.equal(account.linked,true);
  assert.equal(account.contactOnly,true);
  assert.equal(account.password,undefined);
  assert.equal(account.resetLink,undefined);
  assert.equal(authTouched,false);
  assert.equal(storeTouched,false);
  const receipt=buildConfirmation({nome:'Cliente',codice:'ABCDEF',servizio:'Test',quando:'domani',to:'corretta@example.test',account});
  assert.match(receipt.text,/accesso restano invariate/);
  assert.doesNotMatch(receipt.text,/Password temporanea|Esiste già un account con questa email/);
});

test('un uid già collegato non bypassa il controllo del recapito ricevuta',async()=>{
  const result=await provisionCustomerAccount({auth:{},store:{async getAppointment(){return {id:'abcdef123',clienteUid:'originale',clienteEmail:'giusta@example.test'}}},email:'errata@example.test',appointmentId:'abcdef123',codice:'ABCDEF'});
  assert.equal(result.status,'skipped');
  assert.equal(result.reason,'email_mismatch');
});
