/* Backup applicativo paginato: nessuna scrittura sul database. */
(function(root){
'use strict';
const PROJECT='eqtyfnluswalfassmlxd',FORMAT='nexus-application-backup-v2';
async function sha256(text){const bytes=new TextEncoder().encode(text),digest=await crypto.subtle.digest('SHA-256',bytes);return{bytes:bytes.length,sha256:Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,'0')).join('')};}
async function readRpc(db,name,args){
 for(let attempt=0;;attempt++){
  try{const{data,error}=await db.rpc(name,args);if(error)throw error;if(typeof data!=='string')throw Error('Risposta del backup non valida.');return JSON.parse(data);}
  catch(e){const retryable=!e.code||['57014','PGRST003'].includes(e.code);if(attempt>=1||!retryable)throw e;}
 }
}
function validateMetadata(info){
 if(info?.project!==PROJECT||info?.format!==FORMAT||!Array.isArray(info.tables)||!info.tables.length)throw Error('Struttura del backup incompleta o progetto inatteso.');
 const names=new Set();for(const t of info.tables){if(t.schema!=='public'||typeof t.name!=='string'||!t.name||names.has(t.name)||!Number.isSafeInteger(t.row_count)||t.row_count<0||!Array.isArray(t.columns))throw Error('Elenco tabelle del backup non valido.');names.add(t.name);if(t.data_excluded&&t.row_count!==0)throw Error('Archivio PDF non escluso correttamente.');}
}
async function buildZip(db,JSZip,progress=()=>{}){
 progress('Lettura della struttura e conteggio di tutte le tabelle…');
 const info=await readRpc(db,'nexus_backup_metadata');validateMetadata(info);
 const zip=new JSZip(),files={},tableFiles=[],started=info.created_at;let totalRows=0;
 async function addFile(path,content){files[path]=await sha256(content);zip.file(path,content);}
 await addFile('struttura.json',JSON.stringify(info));
 const expectedTotal=info.tables.reduce((n,t)=>n+t.row_count,0);
 for(let index=0;index<info.tables.length;index++){
  const t=info.tables[index],entry={schema:t.schema,name:t.name,row_count:t.row_count,data_excluded:!!t.data_excluded,files:[]};tableFiles.push(entry);
  if(t.data_excluded)continue;
  let offset=0,page=0;
  do{
   progress(`Tabella ${index+1}/${info.tables.length}: ${t.name} · ${offset}/${t.row_count} righe · totale ${totalRows}/${expectedTotal}`);
   const limit=Math.max(1,Math.min(1000,Number(t.page_size)||250));
   const response=await readRpc(db,'nexus_backup_page',{table_name:t.name,page_offset:offset,page_size:limit});
   if(response.table!==t.name||response.offset!==offset||response.row_count!==t.row_count||!Array.isArray(response.rows)||response.rows.length>limit||offset+response.rows.length>t.row_count)throw Error(`Dati di ${t.name} cambiati o risposta incompleta. Ripeti il backup quando gli inserimenti sono fermi.`);
   if(!response.rows.length&&offset<t.row_count)throw Error(`Lettura incompleta di ${t.name}. Il backup non è stato salvato.`);
   if(t.name==='Utenti'&&response.rows.some(r=>Object.hasOwn(r,'Password')))throw Error('Il backup contiene credenziali da escludere.');
   const path=`dati/${String(index+1).padStart(3,'0')}/${String(++page).padStart(6,'0')}.json`;
   await addFile(path,JSON.stringify(response.rows));entry.files.push(path);offset+=response.rows.length;totalRows+=response.rows.length;
  }while(offset<t.row_count);
 }
 progress('Verifica finale delle tabelle e dei conteggi…');
 const finalInfo=await readRpc(db,'nexus_backup_metadata');validateMetadata(finalInfo);
 if(finalInfo.tables.length!==info.tables.length||finalInfo.tables.some(t=>{const old=info.tables.find(o=>o.name===t.name);return !old||old.row_count!==t.row_count||old.data_excluded!==t.data_excluded||JSON.stringify(old.columns)!==JSON.stringify(t.columns);}))throw Error('Le tabelle sono cambiate durante il backup. Riprova quando gli inserimenti sono fermi.');
 if(totalRows!==expectedTotal)throw Error('Il conteggio finale del backup non coincide. Nessun file salvato.');
 const completed=new Date().toISOString();
 zip.file('manifest.json',JSON.stringify({project:PROJECT,format:FORMAT,created_at:started,completed_at:completed,tables:info.tables.length,rows:totalRows,complete:true,snapshot_consistent:false,files,table_files:tableFiles,excluded:info.excluded},null,2));
 zip.file('LEGGIMI.txt',`BACKUP APPLICATIVO NEXUS — FORMATO 2\nInizio: ${started}\nFine lettura: ${completed}\nTabelle: ${info.tables.length}; righe: ${totalRows}\n\nstruttura.json contiene colonne, vincoli, indici, funzioni (anche dello schema nexus_backup_internal), viste, tipi, sequenze, policy, privilegi e riferimenti utenti (ID ed email).\nLa cartella dati contiene pagine JSON: il manifest associa ogni tabella ai relativi file, nell’ordine corretto, e riporta conteggi e checksum SHA-256. Anche le tabelle vuote sono presenti; gli archivi PDF hanno i dati esclusi.\n\nLa lettura avviene per blocchi, con controllo finale dei conteggi e delle colonne. Non è una fotografia transazionale unica: modifiche a valori esistenti durante l’esportazione possono non essere rilevate. Eseguire preferibilmente quando non si stanno inserendo o modificando dati.\n\nSono esclusi i PDF, i file Storage e i dati delle copie storiche delle programmazioni settimanali di Cassano. La programmazione corrente e le ore effettivamente lavorate restano incluse. Non comprende password, credenziali e token Auth, configurazioni dei servizi, chiavi, segreti o codice Edge Functions. Gli accessi vanno riconfigurati in caso di recupero.\nIl file contiene dati riservati: conservarlo nel cloud aziendale con accesso limitato.\nNon è un dump SQL nativo né un ripristino automatico. Recupero tecnico da provare prima su ambiente separato compatibile con Supabase.\n`);
 progress('Compressione del file…');
 const blob=await zip.generateAsync({type:'blob',compression:'DEFLATE',compressionOptions:{level:6},streamFiles:true},({percent})=>progress(`Compressione del file: ${Math.floor(percent)}%`));
 return{blob,tables:info.tables.length,rows:totalRows};
}
root.NexusBackup={buildZip,validateMetadata};if(typeof module!=='undefined')module.exports=root.NexusBackup;
})(typeof globalThis!=='undefined'?globalThis:this);
