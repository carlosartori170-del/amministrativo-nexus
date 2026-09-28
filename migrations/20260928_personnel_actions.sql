create table public."AmministrativoPersone" (
 id uuid primary key default gen_random_uuid(),
 nome text not null check (length(trim(nome)) between 2 and 180),
 sede text not null default 'Da assegnare',
 attivo boolean not null default true,
 creato_il timestamptz not null default now(),
 aggiornato_il timestamptz not null default now()
);
alter table public."AmministrativoPersone" enable row level security;
revoke all on public."AmministrativoPersone" from anon;
grant select,insert,update on public."AmministrativoPersone" to authenticated;
create policy amm_persone_select on public."AmministrativoPersone" for select to authenticated using (exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')));
create policy amm_persone_insert on public."AmministrativoPersone" for insert to authenticated with check (exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')));
create policy amm_persone_update on public."AmministrativoPersone" for update to authenticated using (exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione'))) with check (exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')));
alter table public."AmministrativoDatiPersonale" add column amministrativo_persona_id uuid references public."AmministrativoPersone"(id), add column attivo_override boolean, add column decisione_contratto text check (decisione_contratto is null or decisione_contratto='non_rinnovare');
alter table public."AmministrativoDatiPersonale" drop constraint amm_dati_persona_ref;
alter table public."AmministrativoDatiPersonale" add constraint amm_dati_persona_ref check (
 (dipendente_id is not null and persona_rete_id is null and amministrativo_persona_id is null and persona_key='m:'||dipendente_id::text)
 or (persona_rete_id is not null and dipendente_id is null and amministrativo_persona_id is null and persona_key='r:'||persona_rete_id::text)
 or (amministrativo_persona_id is not null and dipendente_id is null and persona_rete_id is null and persona_key='a:'||amministrativo_persona_id::text)
);
alter table public."AmministrativoScadenzePersonale" add column amministrativo_persona_id uuid references public."AmministrativoPersone"(id), add column rinnovo_da uuid unique references public."AmministrativoScadenzePersonale"(id);
alter table public."AmministrativoScadenzePersonale" drop constraint amministrativo_scad_persona_unica;
alter table public."AmministrativoScadenzePersonale" add constraint amministrativo_scad_persona_unica check (num_nonnulls(dipendente_id,persona_rete_id,amministrativo_persona_id)=1);
alter table public."AmministrativoStoricoFormazione" add column amministrativo_persona_id uuid references public."AmministrativoPersone"(id);
alter table public."AmministrativoStoricoFormazione" drop constraint amm_storico_persona_ref;
alter table public."AmministrativoStoricoFormazione" add constraint amm_storico_persona_ref check (num_nonnulls(dipendente_id,persona_rete_id,amministrativo_persona_id)=1);
create policy amm_local_details_select on public."AmministrativoDatiPersonale" for select to authenticated using (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_details_insert on public."AmministrativoDatiPersonale" for insert to authenticated with check (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_details_update on public."AmministrativoDatiPersonale" for update to authenticated using (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id)) with check (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_deadline_select on public."AmministrativoScadenzePersonale" for select to authenticated using (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_deadline_insert on public."AmministrativoScadenzePersonale" for insert to authenticated with check (creato_da=(select auth.uid()) and amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_deadline_update on public."AmministrativoScadenzePersonale" for update to authenticated using (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id)) with check (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_history_select on public."AmministrativoStoricoFormazione" for select to authenticated using (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_history_insert on public."AmministrativoStoricoFormazione" for insert to authenticated with check (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create policy amm_local_history_update on public."AmministrativoStoricoFormazione" for update to authenticated using (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id)) with check (amministrativo_persona_id is not null and exists(select 1 from public."NexusProfili" p where p."UserID"=(select auth.uid()) and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) and exists(select 1 from public."AmministrativoPersone" a where a.id=amministrativo_persona_id));
create or replace function public.amministrativo_rinnova_contratto(p_persona_key text,p_precedente uuid,p_inizio date,p_scadenza date,p_note text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_old public."AmministrativoScadenzePersonale"%rowtype;v_details public."AmministrativoDatiPersonale"%rowtype;v_new uuid;v_n integer;v_ref uuid;v_m integer;v_r integer;v_a uuid;
begin
 if not exists(select 1 from public."NexusProfili" p where p."UserID"=auth.uid() and p."Attivo" and p."Ruolo" in ('admin','amministrazione')) then raise exception 'Profilo non autorizzato';end if;
 if p_precedente is null or p_inizio is null or p_scadenza is null or p_scadenza<p_inizio then raise exception 'Controlla le date del rinnovo';end if;
 select * into v_old from public."AmministrativoScadenzePersonale" where id=p_precedente and tipo='contratto' and not annullato for update;
 if not found then raise exception 'Contratto precedente non trovato';end if;
 if (case when v_old.amministrativo_persona_id is not null then 'a:'||v_old.amministrativo_persona_id::text when v_old.persona_rete_id is not null then 'r:'||v_old.persona_rete_id::text else 'm:'||v_old.dipendente_id::text end)<>p_persona_key then raise exception 'Persona e contratto non corrispondono';end if;
 select id into v_new from public."AmministrativoScadenzePersonale" where rinnovo_da=p_precedente;
 if v_new is not null then return v_new;end if;
 if p_scadenza<=v_old.data_scadenza then raise exception 'La nuova scadenza deve essere successiva alla precedente';end if;
 if exists(select 1 from public."AmministrativoScadenzePersonale" x where x.tipo='contratto' and not x.annullato and x.id<>p_precedente and x.dipendente_id is not distinct from v_old.dipendente_id and x.persona_rete_id is not distinct from v_old.persona_rete_id and x.amministrativo_persona_id is not distinct from v_old.amministrativo_persona_id and (x.creato_il>v_old.creato_il or (x.creato_il=v_old.creato_il and x.id>p_precedente))) then raise exception 'Esiste già un contratto più recente';end if;
 insert into public."AmministrativoDatiPersonale"(persona_key,dipendente_id,persona_rete_id,amministrativo_persona_id,rinnovi) values(p_persona_key,v_old.dipendente_id,v_old.persona_rete_id,v_old.amministrativo_persona_id,0) on conflict(persona_key) do nothing;
 select * into v_details from public."AmministrativoDatiPersonale" where persona_key=p_persona_key for update;
 if not found then raise exception 'Dati del personale non accessibili';end if;
 v_n:=coalesce(v_details.rinnovi,0);
 if v_n>=4 then raise exception 'Quattro rinnovi già registrati: verifica il contratto';end if;
 insert into public."AmministrativoScadenzePersonale"(dipendente_id,persona_rete_id,amministrativo_persona_id,tipo,data_evento,data_scadenza,note,rinnovo_da) values(v_old.dipendente_id,v_old.persona_rete_id,v_old.amministrativo_persona_id,'contratto',p_inizio,p_scadenza,nullif(trim(p_note),''),p_precedente) returning id into v_new;
 update public."AmministrativoDatiPersonale" set rinnovi=v_n+1,rinnovi_testo=(v_n+1)::text,data_termine_contratto=p_scadenza,termine_testo=to_char(p_scadenza,'DD/MM/YYYY'),attivo_override=true,decisione_contratto=null,aggiornato_il=now() where persona_key=p_persona_key;
 return v_new;
end $$;
revoke all on function public.amministrativo_rinnova_contratto(text,uuid,date,date,text) from public,anon;
grant execute on function public.amministrativo_rinnova_contratto(text,uuid,date,date,text) to authenticated;

-- Nomi modificabili nell'app senza scrivere nell'anagrafica gestionale.
alter table public."AmministrativoDatiPersonale" add column nome_visualizzato text check (nome_visualizzato is null or length(trim(nome_visualizzato)) between 2 and 180);
