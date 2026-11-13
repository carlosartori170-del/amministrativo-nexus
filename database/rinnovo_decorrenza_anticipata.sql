-- Rinnovo con decorrenza anticipata esplicitamente confermata.
-- RPC ordinaria mantenuta invariata; esecuzione con permessi del chiamante e RLS.
CREATE OR REPLACE FUNCTION public.amministrativo_rinnova_contratto_anticipato(p_persona_key text, p_precedente uuid, p_inizio date, p_scadenza date, p_note text, p_conferma_anticipo boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_old public."AmministrativoScadenzePersonale"%rowtype;v_details public."AmministrativoDatiPersonale"%rowtype;v_new uuid;v_n integer;v_original text;v_key text;v_related text[];v_main_id bigint;v_network_id bigint;
begin
 if not exists(select 1 from public."NexusProfili" p where p."UserID"=auth.uid() and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) then raise exception 'Profilo non autorizzato';end if;
 if p_precedente is null or p_inizio is null or (p_scadenza is not null and p_scadenza<p_inizio) then raise exception 'Controlla le date del rinnovo';end if;
 select * into v_old from public."AmministrativoScadenzePersonale" where id=p_precedente and tipo='contratto' and not annullato for update;
 if not found then raise exception 'Contratto precedente non trovato';end if;
 -- Resolve only explicitly linked identities; keep the previous contract intact.
 v_original:=case when v_old.amministrativo_persona_id is not null then 'a:'||v_old.amministrativo_persona_id::text when v_old.persona_rete_id is not null then 'r:'||v_old.persona_rete_id::text else 'm:'||v_old.dipendente_id::text end;
 select l.dipendente_id,l.persona_rete_id into v_main_id,v_network_id from public."AmministrativoCollegamentiPersonale" l where 'm:'||l.dipendente_id::text=v_original or 'r:'||l.persona_rete_id::text=v_original;
 if found then v_key:='m:'||v_main_id::text;v_related:=array[v_key,'r:'||v_network_id::text];else v_key:=v_original;v_related:=array[v_original];end if;
 if p_persona_key is null or not(p_persona_key=any(v_related)) then raise exception 'Persona e contratto non corrispondono';end if;
 select id into v_new from public."AmministrativoScadenzePersonale" where rinnovo_da=p_precedente;
 if v_new is not null then return v_new;end if;
 if v_old.data_scadenza is null then raise exception 'Il contratto è già a tempo indeterminato';end if;
 if p_inizio<=v_old.data_scadenza and p_conferma_anticipo is not true then raise exception 'Conferma esplicitamente la decorrenza anticipata rispetto alla scadenza precedente';end if;
 if v_old.data_evento is not null and p_inizio<v_old.data_evento then raise exception 'Il nuovo inizio non può precedere l’inizio del contratto precedente';end if;
 if p_scadenza is not null and p_scadenza<=v_old.data_scadenza then raise exception 'La nuova scadenza deve essere successiva alla precedente';end if;
 if exists(select 1 from public."AmministrativoScadenzePersonale" x where x.tipo='contratto' and not x.annullato and x.id<>p_precedente and (case when x.amministrativo_persona_id is not null then 'a:'||x.amministrativo_persona_id::text when x.persona_rete_id is not null then 'r:'||x.persona_rete_id::text else 'm:'||x.dipendente_id::text end)=any(v_related) and (x.creato_il>v_old.creato_il or (x.creato_il=v_old.creato_il and x.id>p_precedente))) then raise exception 'Esiste già un contratto più recente';end if;
 insert into public."AmministrativoDatiPersonale"(persona_key,dipendente_id,persona_rete_id,amministrativo_persona_id,rinnovi) values(v_key,coalesce(v_main_id,v_old.dipendente_id),case when v_main_id is null then v_old.persona_rete_id else null end,v_old.amministrativo_persona_id,coalesce((select max(d.rinnovi) from public."AmministrativoDatiPersonale" d where d.persona_key=any(v_related)),0)) on conflict(persona_key) do nothing;
 select * into v_details from public."AmministrativoDatiPersonale" where persona_key=v_key for update;
 if not found then raise exception 'Dati del personale non accessibili';end if;
 v_n:=coalesce(v_details.rinnovi,0);
 if v_n>=4 then raise exception 'Quattro rinnovi già registrati: verifica il contratto';end if;
 insert into public."AmministrativoScadenzePersonale"(dipendente_id,persona_rete_id,amministrativo_persona_id,tipo,data_evento,data_scadenza,note,rinnovo_da) values(v_details.dipendente_id,v_details.persona_rete_id,v_details.amministrativo_persona_id,'contratto',p_inizio,p_scadenza,nullif(concat_ws(E'\n',nullif(trim(p_note),''),case when p_inizio<=v_old.data_scadenza then 'Decorrenza anticipata confermata: scadenza precedente '||to_char(v_old.data_scadenza,'DD/MM/YYYY')||', nuovo inizio '||to_char(p_inizio,'DD/MM/YYYY')||'. Contratto precedente conservato nello storico.' end),''),p_precedente) returning id into v_new;
 update public."AmministrativoDatiPersonale" set rinnovi=v_n+1,rinnovi_testo=(v_n+1)::text,data_termine_contratto=p_scadenza,termine_testo=case when p_scadenza is null then 'indeterminato' else to_char(p_scadenza,'DD/MM/YYYY') end,tipo_soggetto=case when p_scadenza is null then 'Lavoro dipendente a tempo indeterminato' else tipo_soggetto end,attivo_override=true,decisione_contratto=null,data_cessazione=null,aggiornato_il=now() where persona_key=v_key;
 return v_new;
end $function$;
REVOKE ALL ON FUNCTION public.amministrativo_rinnova_contratto_anticipato(text,uuid,date,date,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.amministrativo_rinnova_contratto_anticipato(text,uuid,date,date,text,boolean) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
