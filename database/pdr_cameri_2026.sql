-- Approvata e applicata il 10 novembre 2026. Progetto autorizzato: eqtyfnluswalfassmlxd.
-- Eseguire SOLO dopo approvazione, verifica get_project e prova su clone locale.
-- In assenza del project ref nel database, il controllo esterno e' obbligatorio.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$
DECLARE r text:=current_setting('app.settings.project_ref',true);
BEGIN
 IF r IS NOT NULL AND r<>'' AND r<>'eqtyfnluswalfassmlxd' THEN
  RAISE EXCEPTION 'Progetto non autorizzato: %',r;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public."Attivita" WHERE "ID_Attivita"=56 AND "ID_Reparto"=7 AND "ID_Magazzino"=2)
 OR NOT EXISTS(SELECT 1 FROM public."Attivita" WHERE "ID_Attivita"=63 AND "ID_Reparto"=8 AND "ID_Magazzino"=2)
 OR NOT EXISTS(SELECT 1 FROM public."Attivita" WHERE "ID_Attivita"=70 AND "ID_Reparto"=9 AND "ID_Magazzino"=2)
 THEN RAISE EXCEPTION 'Mappatura Cameri diversa da quella approvata'; END IF;
END $$;

-- Nessun CREATE OR REPLACE: collisioni con oggetti preesistenti fanno abortire.
CREATE SCHEMA nexus_pdr_internal;
REVOKE ALL ON SCHEMA nexus_pdr_internal FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA nexus_pdr_internal TO authenticated;

CREATE FUNCTION nexus_pdr_internal.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT auth.uid() IS NOT NULL AND EXISTS(
 SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=auth.uid()
 AND p."Attivo" IS TRUE AND p."Ruolo"='admin'); $$;

CREATE FUNCTION nexus_pdr_internal.require_admin() RETURNS void
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $$ BEGIN
 IF NOT nexus_pdr_internal.is_admin() THEN
  RAISE EXCEPTION 'Riservato agli amministratori Nexus attivi' USING ERRCODE='42501';
 END IF;
END $$;

CREATE TABLE public."WelfareAnnualeDipendenti" (
 dipendente_id integer NOT NULL REFERENCES public."Dipendenti"("ID_Dipendente") ON DELETE RESTRICT,
 anno integer NOT NULL CHECK(anno=2026),
 figli_a_carico boolean NOT NULL DEFAULT false,
 dichiarazione_verificata boolean NOT NULL DEFAULT false,
 data_dichiarazione date,
 massimale numeric(12,2) GENERATED ALWAYS AS
  (CASE WHEN figli_a_carico AND dichiarazione_verificata THEN 2000.00 ELSE 1000.00 END) STORED,
 fringe_esterni numeric(12,2) NOT NULL DEFAULT 0 CHECK(fringe_esterni>=0),
 pdr_pregresso numeric(12,2) NOT NULL DEFAULT 0 CHECK(pdr_pregresso>=0),
 ricognizione_completa boolean NOT NULL DEFAULT false,
 note_riservate text NOT NULL DEFAULT '',
 aggiornato_da uuid NOT NULL,
 aggiornato_il timestamptz NOT NULL DEFAULT clock_timestamp(),
 revisione bigint NOT NULL DEFAULT 1,
 PRIMARY KEY(dipendente_id,anno),
 CHECK(NOT dichiarazione_verificata OR data_dichiarazione IS NOT NULL)
);

CREATE TABLE public."PdrCameriMoltiplicatori" (
 attivita_id integer PRIMARY KEY REFERENCES public."Attivita"("ID_Attivita") ON DELETE RESTRICT,
 reparto_id integer NOT NULL,
 moltiplicatore numeric CHECK(moltiplicatore>0),
 fonte text NOT NULL,
 CHECK((attivita_id,reparto_id) IN ((56,7),(63,8),(70,9)))
);
INSERT INTO public."PdrCameriMoltiplicatori" VALUES
 (56,7,1,'Gestionale v37 PESI_PDR'),(63,8,1.125,'Gestionale v37 PESI_PDR'),(70,9,6,'Gestionale v37 PESI_PDR');

CREATE TABLE public."PdrCameriMesi" (
 mese date PRIMARY KEY CHECK(mese>=date '2026-01-01' AND mese<date '2027-01-01' AND extract(day FROM mese)=1),
 stato text NOT NULL DEFAULT 'da_classificare'
  CHECK(stato IN ('da_classificare','aperto','chiuso','pagato','storico_pagato')),
 impronta text,
 riepilogo jsonb,
 motivazione text NOT NULL DEFAULT '',
 aggiornato_da uuid,
 aggiornato_il timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public."PdrCameriMesi"(mese)
 SELECT d::date FROM generate_series(timestamp '2026-01-01',timestamp '2026-12-01',interval '1 month') d;

-- Override esplicito e mensile: niente modifiche o fusioni di Dipendenti.
CREATE TABLE public."PdrCameriVoiceMese" (
 mese date NOT NULL REFERENCES public."PdrCameriMesi"(mese) ON DELETE RESTRICT,
 codice_voice integer NOT NULL,
 dipendente_id integer NOT NULL REFERENCES public."Dipendenti"("ID_Dipendente") ON DELETE RESTRICT,
 motivazione text NOT NULL CHECK(length(trim(motivazione))>=5),
 aggiornato_da uuid NOT NULL,
 aggiornato_il timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(mese,codice_voice)
);

CREATE TABLE public."PdrCameriEccezioni" (
 mese date NOT NULL REFERENCES public."PdrCameriMesi"(mese) ON DELETE RESTRICT,
 dipendente_id integer NOT NULL REFERENCES public."Dipendenti"("ID_Dipendente") ON DELETE RESTRICT,
 autorizzata boolean NOT NULL,
 tipo text NOT NULL CHECK(tipo IN ('ricovero','evento_grave')),
 motivazione_riservata text NOT NULL CHECK(length(trim(motivazione_riservata))>=5),
 autorizzato_da uuid NOT NULL,
 autorizzato_il timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(mese,dipendente_id)
);

CREATE TABLE public."PdrCameriRisultati" (
 mese date NOT NULL REFERENCES public."PdrCameriMesi"(mese) ON DELETE RESTRICT,
 dipendente_id integer NOT NULL REFERENCES public."Dipendenti"("ID_Dipendente") ON DELETE RESTRICT,
 welfare numeric(12,2) NOT NULL CHECK(welfare>=0),
 premio_lordo numeric(12,2) NOT NULL CHECK(premio_lordo>=0),
 snapshot jsonb NOT NULL,
 PRIMARY KEY(mese,dipendente_id)
);

CREATE TABLE public."PdrCameriAudit" (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 oggetto text NOT NULL,
 chiave text NOT NULL,
 prima jsonb,
 dopo jsonb,
 autore uuid NOT NULL,
 data_evento timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- RLS + grants specifici: nessun cambio ai default globali o alle policy esistenti.
DO $$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['WelfareAnnualeDipendenti','PdrCameriMoltiplicatori','PdrCameriMesi',
  'PdrCameriVoiceMese','PdrCameriEccezioni','PdrCameriRisultati','PdrCameriAudit'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated',t);
  EXECUTE format('CREATE POLICY pdr_admin_select ON public.%I FOR SELECT TO authenticated USING ((SELECT nexus_pdr_internal.is_admin()))',t);
 END LOOP;
END $$;

-- Trigger invoker: chiamato solo dalle RPC definer; nessun INSERT audit dal client.
CREATE FUNCTION nexus_pdr_internal.audit_row() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$ BEGIN
 PERFORM nexus_pdr_internal.require_admin();
 INSERT INTO public."PdrCameriAudit"(oggetto,chiave,prima,dopo,autore)
 VALUES(TG_TABLE_NAME,coalesce(to_jsonb(NEW)->>'dipendente_id',to_jsonb(NEW)->>'mese','config'),
  CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,
  CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END,auth.uid());
 RETURN NULL;
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['WelfareAnnualeDipendenti','PdrCameriMesi','PdrCameriVoiceMese','PdrCameriEccezioni','PdrCameriRisultati'] LOOP
  EXECUTE format('CREATE TRIGGER pdr_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION nexus_pdr_internal.audit_row()',t);
 END LOOP;
END $$;

-- Scaglioni addendum: percentuali letterali, non h/150 ne' 5/6.
CREATE FUNCTION nexus_pdr_internal.fattore(h numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT CASE WHEN h>=150 THEN 1 WHEN h>=125 THEN .8333 WHEN h>=100 THEN .6667
 WHEN h>=75 THEN .5 WHEN h>=50 THEN .3333 WHEN h>=25 THEN .1667 ELSE 0 END; $$;

-- Interpretazione continua proposta: <=180 zero, (180,190] prima fascia ecc.
-- Esplicitamente da approvare: i documenti riportano estremi interi 181-190,191-200...
CREATE FUNCTION nexus_pdr_internal.fascia(p numeric) RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT CASE WHEN p IS NULL OR p<=180 THEN 0 ELSE least(12,ceil((p-180)/10)::integer) END; $$;

CREATE FUNCTION nexus_pdr_internal.saldo(p_dip integer) RETURNS numeric
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT greatest(0,w.massimale-w.fringe_esterni-w.pdr_pregresso-coalesce((
 SELECT sum(r.welfare) FROM public."PdrCameriRisultati" r
 JOIN public."PdrCameriMesi" m ON m.mese=r.mese WHERE r.dipendente_id=p_dip
 AND m.stato IN ('chiuso','pagato')),0))
 FROM public."WelfareAnnualeDipendenti" w WHERE w.dipendente_id=p_dip AND w.anno=2026
 AND w.ricognizione_completa; $$;

-- Ricostruzione timeline identica a _giorniDelBattesimo, con tutti i battesimi
-- nell'ordine OrdineRiga, ID_Battesimo. PreTurno e' provvisorio e resta escluso.
CREATE FUNCTION nexus_pdr_internal.sorgenti(p_mese date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$
WITH timeline AS (
 SELECT t."ID_Turno",t."ID_Dipendente",t."DataInizio",t."OraInizio",
  b."ID_Battesimo",b."ID_Attivita",b."ID_Reparto",b."OreBattezzate",
  coalesce(sum(coalesce(b."OreBattezzate",0)) OVER(PARTITION BY t."ID_Turno"
   ORDER BY coalesce(b."OrdineRiga",0),b."ID_Battesimo" ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) offset_ore
 FROM public."TurniGiornalieri" t JOIN public."BattesimiTurno" b ON b."ID_Turno"=t."ID_Turno"
 WHERE t."ID_Magazzino"=2 AND t."DataInizio">=p_mese-1
 AND t."DataInizio"<(p_mese+interval '1 month')::date
), intervalli AS (
 SELECT x.*,x."DataInizio"+coalesce(nullif(x."OraInizio",'')::time,time '00:00')
  +make_interval(secs=>CASE WHEN coalesce(x."OraInizio",'')='' THEN 0 ELSE x.offset_ore*3600 END::double precision) inizio
 FROM timeline x WHERE x."OreBattezzate">0
 AND (x."ID_Attivita",x."ID_Reparto") IN ((56,7),(63,8),(70,9))
), giornaliero AS (
 SELECT i."ID_Dipendente" dipendente_id,i."ID_Attivita" attivita_id,i."ID_Battesimo" battesimo_id,
  g.giorno::date data,
  CASE WHEN coalesce(i."OraInizio",'')='' THEN i."OreBattezzate"
   ELSE extract(epoch FROM (least(i.inizio+make_interval(secs=>(i."OreBattezzate"*3600)::double precision),g.giorno+interval '1 day')
    -greatest(i.inizio,g.giorno)))/3600 END ore,
  coalesce(i."OraInizio",'')='' or i."OraInizio" !~ '^\d{1,2}:\d{2}(:\d{2})?$' or i.offset_ore+i."OreBattezzate">24 timeline_anomala
 FROM intervalli i CROSS JOIN LATERAL generate_series(date_trunc('day',i.inizio),
  CASE WHEN coalesce(i."OraInizio",'')='' THEN date_trunc('day',i.inizio)
  ELSE date_trunc('day',i.inizio+make_interval(secs=>(i."OreBattezzate"*3600)::double precision)-interval '1 microsecond') END,
  interval '1 day') g(giorno)
 WHERE g.giorno::date>=p_mese AND g.giorno::date<(p_mese+interval '1 month')::date
), candidati AS (
 SELECT d.* FROM public."Dipendenti" d WHERE 2=ANY(d."Magazzini")
 OR EXISTS(SELECT 1 FROM giornaliero g WHERE g.dipendente_id=d."ID_Dipendente")
 OR EXISTS(SELECT 1 FROM public."PdrCameriVoiceMese" v WHERE v.mese=p_mese AND v.dipendente_id=d."ID_Dipendente")
), automatici AS (
 SELECT "CodiceVoice" codice_voice,min("ID_Dipendente") dipendente_id
 FROM candidati WHERE "CodiceVoice" IS NOT NULL GROUP BY 1 HAVING count(*)=1
), mappa AS (
 SELECT codice_voice,dipendente_id FROM public."PdrCameriVoiceMese" WHERE mese=p_mese
 UNION ALL SELECT a.* FROM automatici a WHERE NOT EXISTS(
 SELECT 1 FROM public."PdrCameriVoiceMese" v WHERE v.mese=p_mese AND v.codice_voice=a.codice_voice)
), produzione AS (
 SELECT p.*,m.dipendente_id FROM public."ProduzioneOperatori" p LEFT JOIN mappa m ON m.codice_voice=p."CodiceVoice"
 WHERE p."ID_Magazzino"=2 AND p."DataProduzione">=p_mese AND p."DataProduzione"<(p_mese+interval '1 month')::date
 AND p."ID_Attivita" IN (56,63,70)
)
SELECT jsonb_build_object(
 'dipendenti',coalesce((SELECT jsonb_agg(jsonb_build_object('id',"ID_Dipendente",'nome',"Nome",'voice',"CodiceVoice") ORDER BY "ID_Dipendente") FROM candidati),'[]'::jsonb),
 'ore',coalesce((SELECT jsonb_agg(to_jsonb(g) ORDER BY dipendente_id,data,attivita_id,battesimo_id) FROM giornaliero g),'[]'::jsonb),
 'produzione',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY "ID_Produzione") FROM produzione p),'[]'::jsonb),
 'voice_duplicati',coalesce((SELECT jsonb_agg(codice_voice ORDER BY codice_voice) FROM(
  SELECT "CodiceVoice" codice_voice FROM candidati WHERE "CodiceVoice" IS NOT NULL GROUP BY 1 HAVING count(*)>1)z),'[]'::jsonb),
 'ore_non_valide',coalesce((SELECT jsonb_agg("ID_Battesimo" ORDER BY "ID_Battesimo") FROM timeline WHERE "OreBattezzate" IS NULL OR "OreBattezzate"<0),'[]'::jsonb)
); $$;

-- Motore unico server-side. Non espone figli, dichiarazioni, note, date di assunzione.
CREATE FUNCTION nexus_pdr_internal.calcola(p_mese date) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $$
DECLARE s jsonb; righe jsonb:='[]'; anomalie jsonb:='[]'; d record; a record; x record;
 h numeric; c numeric; prod numeric; f integer; q numeric; lordo numeric; wt numeric;
 disponibile numeric; w numeric; convertito numeric; residuo numeric;
 mal boolean; ec boolean; amm boolean; assunto date; n_personale integer;
 flags jsonb; dettagli jsonb; v_ore numeric; v_colli numeric; peso numeric;
 fingerprint text; w_snapshot jsonb; e_snapshot jsonb; map_snapshot jsonb; cfg jsonb;
BEGIN
 PERFORM nexus_pdr_internal.require_admin();
 IF p_mese IS NULL OR NOT EXISTS(SELECT 1 FROM public."PdrCameriMesi" WHERE mese=p_mese AND stato='aperto') THEN
  RAISE EXCEPTION 'Mese non aperto: storico e pagato non ricalcolabili';
 END IF;
 s:=nexus_pdr_internal.sorgenti(p_mese);
 FOR d IN SELECT * FROM jsonb_to_recordset(s->'dipendenti') AS z(id integer,nome text,voice integer) ORDER BY id LOOP
  flags:='[]'; dettagli:='[]'; h:=0; c:=0;
  IF d.voice IS NULL THEN flags:=flags||jsonb_build_array('codice_voice_mancante'); END IF;
  IF (s->'voice_duplicati') @> jsonb_build_array(d.voice) THEN flags:=flags||jsonb_build_array('codice_voice_duplicato_verificare_mappa'); END IF;
  FOR a IN SELECT * FROM (VALUES(56,7),(63,8),(70,9))v(id,rep) LOOP
   SELECT coalesce(sum(z.ore),0) INTO v_ore FROM jsonb_to_recordset(s->'ore') AS z(dipendente_id integer,attivita_id integer,ore numeric) WHERE z.dipendente_id=d.id AND z.attivita_id=a.id;
   SELECT coalesce(sum(z."Colli"),0) INTO v_colli FROM jsonb_to_recordset(s->'produzione') AS z(dipendente_id integer,"ID_Attivita" integer,"Colli" numeric) WHERE z.dipendente_id=d.id AND z."ID_Attivita"=a.id;
   SELECT moltiplicatore INTO peso FROM public."PdrCameriMoltiplicatori" WHERE attivita_id=a.id AND reparto_id=a.rep;
   IF peso IS NULL THEN flags:=flags||jsonb_build_array('moltiplicatore_mancante_'||a.id); END IF;
   h:=h+v_ore; c:=c+v_colli*coalesce(peso,0);
   -- Anomalie rilevate a livello giorno-attivita', anche se il totale mensile si compensa.
   FOR x IN
    WITH o AS (SELECT data,coalesce(sum(ore),0) ore FROM jsonb_to_recordset(s->'ore') AS z(dipendente_id integer,attivita_id integer,data date,ore numeric) WHERE dipendente_id=d.id AND attivita_id=a.id GROUP BY data),
    p AS (SELECT "DataProduzione" data,count(*) FILTER(WHERE "Colli" IS NOT NULL) n,sum("Colli") colli FROM jsonb_to_recordset(s->'produzione') AS z(dipendente_id integer,"ID_Attivita" integer,"DataProduzione" date,"Colli" numeric) WHERE dipendente_id=d.id AND "ID_Attivita"=a.id GROUP BY 1)
    SELECT coalesce(o.data,p.data) data,CASE WHEN o.ore>0 AND coalesce(p.n,0)=0 THEN 'ore_senza_colli' WHEN coalesce(p.n,0)>0 AND coalesce(o.ore,0)=0 THEN 'colli_senza_ore' END tipo
    FROM o FULL JOIN p USING(data)
   LOOP
    IF x.tipo IS NOT NULL THEN dettagli:=dettagli||jsonb_build_array(jsonb_build_object('data',x.data,'attivita',a.id,'tipo',x.tipo)); END IF;
   END LOOP;
  END LOOP;
  IF EXISTS(SELECT 1 FROM jsonb_to_recordset(s->'ore') AS z(dipendente_id integer,timeline_anomala boolean) WHERE dipendente_id=d.id AND timeline_anomala) THEN flags:=flags||jsonb_build_array('timeline_da_verificare'); END IF;
  prod:=CASE WHEN h>0 THEN c/h END; f:=nexus_pdr_internal.fascia(prod); q:=nexus_pdr_internal.fattore(h);
  SELECT min(data_assunzione),count(*) INTO assunto,n_personale FROM public."AmministrativoDatiPersonale" WHERE dipendente_id=d.id;
  amm:=n_personale=1 AND assunto IS NOT NULL AND assunto<=p_mese;
  IF assunto IS NULL OR n_personale<>1 THEN flags:=flags||jsonb_build_array('data_assunzione_non_verificabile');
  ELSIF assunto>p_mese THEN flags:=flags||jsonb_build_array('mese_ingresso_non_maturato'); END IF;
  -- Non filtrare il magazzino dell'assenza: la malattia della persona conta anche
  -- se registrata con un altro magazzino o ID_Magazzino nullo.
  SELECT EXISTS(SELECT 1 FROM public."Assenze" WHERE "ID_Dipendente"=d.id
   AND "Data">=p_mese AND "Data"<(p_mese+interval '1 month')::date
   AND lower(trim("TipoAssenza"))='malattia') INTO mal;
  SELECT coalesce((SELECT autorizzata FROM public."PdrCameriEccezioni" WHERE mese=p_mese AND dipendente_id=d.id),false) INTO ec;
  lordo:=round(45.39*f*q,2); wt:=round(60*f*q,2);
  IF (mal AND NOT ec) OR NOT amm THEN lordo:=0; wt:=0; END IF;
  disponibile:=nexus_pdr_internal.saldo(d.id);
  IF disponibile IS NULL THEN flags:=flags||jsonb_build_array('ricognizione_welfare_incompleta'); END IF;
  w:=least(wt,coalesce(disponibile,0));
  convertito:=CASE WHEN wt>0 THEN round(w*lordo/wt,2) ELSE 0 END;
  residuo:=lordo-convertito;
  righe:=righe||jsonb_build_array(jsonb_build_object('dipendente_id',d.id,'nome',d.nome,
   'ore',h,'colli_ponderati',c,'produttivita',prod,'fascia',f,'fattore_ore',q,
   'malattia',mal,'eccezione',ec,'welfare_teorico',wt,'lordo_previsto',lordo,
   'welfare_disponibile',coalesce(disponibile,0),'welfare',w,'quota_lorda_convertita',convertito,'premio_lordo',residuo,
   'anomalie',flags,'dettagli_anomalie',dettagli,
   'stato',CASE WHEN jsonb_array_length(flags)>0 OR jsonb_array_length(dettagli)>0 THEN 'provvisorio_con_anomalie' ELSE 'calcolato' END));
 END LOOP;
 SELECT coalesce(jsonb_agg(to_jsonb(z) ORDER BY z.dipendente_id),'[]') INTO w_snapshot FROM public."WelfareAnnualeDipendenti" z WHERE anno=2026;
 SELECT coalesce(jsonb_agg(to_jsonb(z) ORDER BY z.dipendente_id),'[]') INTO e_snapshot FROM public."PdrCameriEccezioni" z WHERE mese=p_mese;
 SELECT coalesce(jsonb_agg(to_jsonb(z) ORDER BY z.codice_voice),'[]') INTO map_snapshot FROM public."PdrCameriVoiceMese" z WHERE mese=p_mese;
 SELECT jsonb_agg(to_jsonb(z) ORDER BY attivita_id) INTO cfg FROM public."PdrCameriMoltiplicatori" z;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(s->'produzione') AS z(dipendente_id integer)) THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('produzione_id',z."ID_Produzione",'voice',z."CodiceVoice",'tipo','colli_non_attribuiti') ORDER BY z."ID_Produzione"),'[]') INTO anomalie
  FROM jsonb_to_recordset(s->'produzione') AS z(dipendente_id integer,"ID_Produzione" integer,"CodiceVoice" integer) WHERE dipendente_id IS NULL;
 END IF;
 IF jsonb_array_length(s->'ore_non_valide')>0 THEN anomalie:=anomalie||jsonb_build_array(jsonb_build_object('tipo','ore_non_valide','battesimi',s->'ore_non_valide')); END IF;
 -- L'impronta non rivela le informazioni riservate usate per invalidare anteprime vecchie.
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('sorgenti',s,'righe',righe,
  'welfare',w_snapshot,'eccezioni',e_snapshot,'mappa',map_snapshot,'pesi',cfg,'versione','pdr2026-v1')::text,'UTF8')),'hex');
 RETURN jsonb_build_object('mese',p_mese,'versione','pdr2026-v1','impronta',fingerprint,'righe',righe,'anomalie',anomalie);
END $$;

-- Un solo punto mutativo privato, operazioni esplicite, nessun SQL dinamico.
CREATE FUNCTION nexus_pdr_internal.scrivi(p_operazione text,p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' SET statement_timeout='55s'
AS $$
DECLARE m date; st text; dip integer; attuale public."WelfareAnnualeDipendenti"%rowtype;
 v public."WelfareAnnualeDipendenti"%rowtype; risultato jsonb; r jsonb; usato numeric;
BEGIN
 PERFORM nexus_pdr_internal.require_admin();
 -- Stesso lock per schede welfare, mappature, eccezioni e tutte le chiusure 2026.
 PERFORM pg_advisory_xact_lock(2026,724602);
 m:=(p->>'mese')::date; dip:=(p->>'dipendente_id')::integer;
 IF p_operazione='welfare' THEN
  IF p->>'anno'<>'2026' OR (p->>'anno') IS NULL THEN RAISE EXCEPTION 'Solo anno 2026'; END IF;
  SELECT * INTO attuale FROM public."WelfareAnnualeDipendenti" WHERE dipendente_id=dip AND anno=2026 FOR UPDATE;
  IF coalesce(attuale.revisione,0)<>coalesce((p->>'revisione_attesa')::bigint,-1) THEN RAISE EXCEPTION 'Scheda modificata: ricaricare'; END IF;
  v:=jsonb_populate_record(NULL::public."WelfareAnnualeDipendenti",p);
  -- Nessun massimale, autore, revisione o totale modificabile dal client.
  INSERT INTO public."WelfareAnnualeDipendenti"(dipendente_id,anno,figli_a_carico,dichiarazione_verificata,data_dichiarazione,
   fringe_esterni,pdr_pregresso,ricognizione_completa,note_riservate,aggiornato_da,revisione)
  VALUES(dip,2026,coalesce(v.figli_a_carico,false),coalesce(v.dichiarazione_verificata,false),v.data_dichiarazione,
   coalesce(v.fringe_esterni,0),coalesce(v.pdr_pregresso,0),coalesce(v.ricognizione_completa,false),coalesce(v.note_riservate,''),auth.uid(),coalesce(attuale.revisione,0)+1)
  ON CONFLICT(dipendente_id,anno) DO UPDATE SET figli_a_carico=excluded.figli_a_carico,
   dichiarazione_verificata=excluded.dichiarazione_verificata,data_dichiarazione=excluded.data_dichiarazione,
   fringe_esterni=excluded.fringe_esterni,pdr_pregresso=excluded.pdr_pregresso,ricognizione_completa=excluded.ricognizione_completa,
   note_riservate=excluded.note_riservate,aggiornato_da=auth.uid(),aggiornato_il=clock_timestamp(),revisione=excluded.revisione;
  SELECT coalesce(sum(welfare),0) INTO usato FROM public."PdrCameriRisultati" WHERE dipendente_id=dip;
  -- I dati effettivi devono poter rappresentare anche un superamento pregresso.
  -- Il residuo viene saturato a zero e si restituisce segnalazione, senza alterare pagati.
  RETURN jsonb_build_object('ok',true,'superamento',EXISTS(SELECT 1 FROM public."WelfareAnnualeDipendenti" WHERE dipendente_id=dip AND anno=2026 AND fringe_esterni+pdr_pregresso+usato>massimale));
 END IF;
 SELECT stato INTO st FROM public."PdrCameriMesi" WHERE mese=m FOR UPDATE;
 IF st IS NULL THEN RAISE EXCEPTION 'Mese 2026 non valido'; END IF;
 IF p_operazione='classifica' THEN
  IF st<>'da_classificare' OR coalesce(length(trim(p->>'motivazione')),0)<5 THEN RAISE EXCEPTION 'Classificazione non consentita o motivazione assente'; END IF;
  IF p->>'stato' IS NULL OR p->>'stato' NOT IN ('aperto','storico_pagato') THEN RAISE EXCEPTION 'Stato non valido'; END IF;
  UPDATE public."PdrCameriMesi" SET stato=p->>'stato',motivazione=p->>'motivazione',aggiornato_da=auth.uid(),aggiornato_il=clock_timestamp() WHERE mese=m;
  RETURN jsonb_build_object('ok',true);
 ELSIF p_operazione='pagato' THEN
  IF st<>'chiuso' THEN RAISE EXCEPTION 'Solo mesi chiusi'; END IF;
  IF coalesce(length(trim(p->>'motivazione')),0)<5 THEN RAISE EXCEPTION 'Riferimento pagamento richiesto'; END IF;
  UPDATE public."PdrCameriMesi" SET stato='pagato',motivazione=p->>'motivazione',aggiornato_da=auth.uid(),aggiornato_il=clock_timestamp() WHERE mese=m;
  RETURN jsonb_build_object('ok',true);
 END IF;
 IF st<>'aperto' THEN RAISE EXCEPTION 'Mese protetto: nessuna modifica o ricalcolo'; END IF;
 IF p_operazione='voice' THEN
  IF NOT EXISTS(SELECT 1 FROM public."Dipendenti" WHERE "ID_Dipendente"=dip AND (2=ANY("Magazzini") OR EXISTS(SELECT 1 FROM public."TurniGiornalieri" WHERE "ID_Magazzino"=2 AND "ID_Dipendente"=dip AND "DataInizio">=m-1 AND "DataInizio"<(m+interval '1 month')::date))) THEN RAISE EXCEPTION 'Dipendente non appartenente a Cameri nel periodo verificabile'; END IF;
  INSERT INTO public."PdrCameriVoiceMese" VALUES(m,(p->>'codice_voice')::integer,dip,p->>'motivazione',auth.uid(),clock_timestamp())
  ON CONFLICT(mese,codice_voice) DO UPDATE SET dipendente_id=excluded.dipendente_id,motivazione=excluded.motivazione,aggiornato_da=auth.uid(),aggiornato_il=clock_timestamp();
 ELSIF p_operazione='eccezione' THEN
  INSERT INTO public."PdrCameriEccezioni" VALUES(m,dip,(p->>'autorizzata')::boolean,p->>'tipo',p->>'motivazione_riservata',auth.uid(),clock_timestamp())
  ON CONFLICT(mese,dipendente_id) DO UPDATE SET autorizzata=excluded.autorizzata,tipo=excluded.tipo,motivazione_riservata=excluded.motivazione_riservata,autorizzato_da=auth.uid(),autorizzato_il=clock_timestamp();
 ELSIF p_operazione='chiudi' THEN
  IF m>=date_trunc('month',current_timestamp AT TIME ZONE 'Europe/Rome')::date THEN RAISE EXCEPTION 'Mese non terminato'; END IF;
  IF EXISTS(SELECT 1 FROM public."PdrCameriMesi" WHERE mese<m AND stato NOT IN ('chiuso','pagato','storico_pagato')) THEN RAISE EXCEPTION 'Classificare/chiudere prima i mesi precedenti'; END IF;
  -- Blocca scritture concorrenti SOLO per la breve transazione di chiusura.
  LOCK TABLE public."TurniGiornalieri",public."BattesimiTurno",public."ProduzioneOperatori",
   public."Dipendenti",public."AmministrativoDatiPersonale",public."Assenze" IN SHARE MODE;
  risultato:=nexus_pdr_internal.calcola(m);
  IF (p->>'impronta') IS DISTINCT FROM (risultato->>'impronta') THEN RAISE EXCEPTION 'Anteprima superata: ricalcolare e verificare'; END IF;
  IF (jsonb_array_length(risultato->'anomalie')>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(risultato->'righe') z WHERE z->>'stato'='provvisorio_con_anomalie'))
   AND coalesce(length(trim(p->>'presa_visione_anomalie')),0)<5 THEN RAISE EXCEPTION 'Presa visione motivata delle anomalie richiesta'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(risultato->'righe') LOOP
   INSERT INTO public."PdrCameriRisultati" VALUES(m,(r->>'dipendente_id')::integer,(r->>'welfare')::numeric,(r->>'premio_lordo')::numeric,r);
  END LOOP;
  UPDATE public."PdrCameriMesi" SET stato='chiuso',impronta=risultato->>'impronta',riepilogo=risultato,
   motivazione=coalesce(p->>'presa_visione_anomalie','Chiusura senza anomalie'),aggiornato_da=auth.uid(),aggiornato_il=clock_timestamp() WHERE mese=m;
  RETURN risultato;
 ELSE RAISE EXCEPTION 'Operazione non prevista';
 END IF;
 RETURN jsonb_build_object('ok',true);
END $$;

-- Wrapper API INVOKER: il definer e' confinato nello schema non esposto.
CREATE FUNCTION public.nexus_pdr_anteprima(p_mese date) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=''
AS $$ SELECT nexus_pdr_internal.calcola(p_mese); $$;
CREATE FUNCTION public.nexus_pdr_operazione(p_operazione text,p_dati jsonb) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=''
AS $$ SELECT nexus_pdr_internal.scrivi(p_operazione,p_dati); $$;

CREATE VIEW public."WelfareAnnualeRiepilogo" WITH(security_invoker=true) AS
 SELECT w.*,w.pdr_pregresso+coalesce(r.pagato,0) AS welfare_pdr_utilizzato,
 coalesce(r.impegnato,0) AS welfare_pdr_impegnato,
 w.fringe_esterni+w.pdr_pregresso+coalesce(r.pagato,0) AS totale_erogato,
 greatest(0,w.massimale-w.fringe_esterni-w.pdr_pregresso-coalesce(r.pagato,0)-coalesce(r.impegnato,0)) AS residuo_disponibile,
 w.fringe_esterni+w.pdr_pregresso+coalesce(r.pagato,0)+coalesce(r.impegnato,0)>w.massimale AS superamento
 FROM public."WelfareAnnualeDipendenti" w LEFT JOIN LATERAL(
  SELECT sum(x.welfare) FILTER(WHERE m.stato='pagato') pagato,
   sum(x.welfare) FILTER(WHERE m.stato='chiuso') impegnato
  FROM public."PdrCameriRisultati" x JOIN public."PdrCameriMesi" m ON m.mese=x.mese
  WHERE x.dipendente_id=w.dipendente_id
 ) r ON true;
REVOKE ALL ON public."WelfareAnnualeRiepilogo" FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public."WelfareAnnualeRiepilogo" TO authenticated;

-- Privilegi funzione stretti, incluse eredita' da default privileges.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nexus_pdr_internal FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION nexus_pdr_internal.is_admin(),nexus_pdr_internal.calcola(date),nexus_pdr_internal.scrivi(text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.nexus_pdr_anteprima(date),public.nexus_pdr_operazione(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.nexus_pdr_anteprima(date),public.nexus_pdr_operazione(text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
