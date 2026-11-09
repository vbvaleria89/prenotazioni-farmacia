// Bridge Google Calendar (GIS token client) per Flutter web. Nessun secret qui.
(function(){
  const CLIENT_ID='444833221252-pivii37uqhrshlhtfq4a5i83kl5efef7.apps.googleusercontent.com';
  const CAL_ID='1194e4eb297f05196e148f42f5d52c08dd3932255c83ecf81926548f008f9b99@group.calendar.google.com';
  const SCOPE='https://www.googleapis.com/auth/calendar';
  const API='https://www.googleapis.com/calendar/v3';
  let tc=null;
  function tok(){const t=JSON.parse(sessionStorage.getItem('gcal_tok')||'null');return t&&t.exp>Date.now()?t.v:null;}
  async function call(method,path,body){
    const t=tok(); if(!t) throw new Error('not_connected');
    const r=await fetch(API+path,{method,headers:{Authorization:'Bearer '+t,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
    if(r.status===401){sessionStorage.removeItem('gcal_tok');throw new Error('not_connected');}
    if(!r.ok && !(method==='DELETE' && (r.status===410 || r.status===404))) throw new Error('http_'+r.status);
    return r.status===204||method==='DELETE'?'':JSON.stringify(await r.json());
  }
  window.gcal={
    isConnected:()=>!!tok(),
    connect:()=>new Promise((res,rej)=>{
      if(!window.google||!google.accounts) return rej(new Error('gis_not_loaded'));
      tc=google.accounts.oauth2.initTokenClient({client_id:CLIENT_ID,scope:SCOPE,callback:(r)=>{
        if(r.error) return rej(new Error(r.error));
        sessionStorage.setItem('gcal_tok',JSON.stringify({v:r.access_token,exp:Date.now()+(r.expires_in-60)*1000}));res(true);}});
      tc.requestAccessToken({prompt:''});
    }),
    disconnect:()=>{const t=tok();if(t&&window.google)google.accounts.oauth2.revoke(t,()=>{});sessionStorage.removeItem('gcal_tok');},
    createEvent:async(summary,description,startIso,endIso)=>JSON.parse(await call('POST','/calendars/'+encodeURIComponent(CAL_ID)+'/events',{summary,description,start:{dateTime:startIso},end:{dateTime:endIso}})).id,
    updateEvent:async(id,summary,description,startIso,endIso)=>{
      const body={summary,description,start:{dateTime:startIso},end:{dateTime:endIso}};
      const path='/calendars/'+encodeURIComponent(CAL_ID)+'/events';
      try { return JSON.parse(await call('PATCH',path+'/'+encodeURIComponent(id),body)).id; }
      catch(e) {
        if(e.message!=='http_404' && e.message!=='http_410') throw e;
        return JSON.parse(await call('POST',path,body)).id;
      }
    },
    deleteEvent:(id)=>call('DELETE','/calendars/'+encodeURIComponent(CAL_ID)+'/events/'+encodeURIComponent(id)),
    busy:async(minIso,maxIso)=>{const j=JSON.parse(await call('POST','/freeBusy',{timeMin:minIso,timeMax:maxIso,items:[{id:CAL_ID}]}));return JSON.stringify((j.calendars[CAL_ID]||{}).busy||[]);}
  };
})();
