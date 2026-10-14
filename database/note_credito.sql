-- Note di credito ricevute: importi del documento positivi, storni di costo negativi.
ALTER TABLE public."AmministrativoFatture" ADD COLUMN fattura_riferimento_id uuid REFERENCES public."AmministrativoFatture"(id);
ALTER TABLE public."AmministrativoFatture" ADD CONSTRAINT fattura_riferimento_diversa CHECK (fattura_riferimento_id IS DISTINCT FROM id);
CREATE INDEX amministrativo_fattura_riferimento_idx ON public."AmministrativoFatture"(fattura_riferimento_id) WHERE fattura_riferimento_id IS NOT NULL;
ALTER TABLE public."AmministrativoMovimenti" ADD COLUMN storno boolean NOT NULL DEFAULT false;
ALTER TABLE public."AmministrativoMovimenti" DROP CONSTRAINT "AmministrativoMovimenti_importo_check";
ALTER TABLE public."AmministrativoMovimenti" ADD CONSTRAINT "AmministrativoMovimenti_importo_check" CHECK ((NOT storno AND importo > 0) OR (storno AND tipo='costo' AND fattura_id IS NOT NULL AND fattura_emessa_id IS NULL AND importo<0));
CREATE FUNCTION public.nexus_tipo_nota_credito(t text) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT coalesce(upper(trim(t)) ~ '^TD0[48]($|[^0-9])' OR t ~* 'nota[[:space:]]+di[[:space:]]+credito',false) $$;
CREATE FUNCTION public.nexus_verifica_nota_credito() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE f public."AmministrativoFatture"; target public."AmministrativoFatture";
BEGIN
 IF TG_TABLE_NAME='AmministrativoFatture' THEN
  IF NEW.fattura_riferimento_id IS NOT NULL THEN
   SELECT * INTO target FROM public."AmministrativoFatture" WHERE id=NEW.fattura_riferimento_id FOR SHARE;
   IF NOT public.nexus_tipo_nota_credito(NEW.tipo_documento) OR target.id IS NULL OR public.nexus_tipo_nota_credito(target.tipo_documento) OR NEW.partita_iva IS DISTINCT FROM target.partita_iva THEN RAISE EXCEPTION 'Scegli una fattura dello stesso fornitore.'; END IF;
  END IF;
  IF TG_OP='UPDATE' AND (NEW.tipo_documento IS DISTINCT FROM OLD.tipo_documento OR NEW.partita_iva IS DISTINCT FROM OLD.partita_iva) AND (EXISTS(SELECT 1 FROM public."AmministrativoFatture" WHERE fattura_riferimento_id=NEW.id) OR EXISTS(SELECT 1 FROM public."AmministrativoMovimenti" WHERE fattura_id=NEW.id)) THEN RAISE EXCEPTION 'Tipo e fornitore non modificabili per un documento collegato.'; END IF;
 ELSE
  IF NEW.fattura_id IS NOT NULL THEN SELECT * INTO f FROM public."AmministrativoFatture" WHERE id=NEW.fattura_id FOR SHARE; END IF;
  IF NEW.storno IS DISTINCT FROM public.nexus_tipo_nota_credito(f.tipo_documento) THEN RAISE EXCEPTION 'Segno del movimento incompatibile con il documento.'; END IF;
  IF NEW.storno THEN
   IF f.fattura_riferimento_id IS NULL THEN RAISE EXCEPTION 'Abbina prima la fattura di riferimento.'; END IF;
   IF NEW.importo IS DISTINCT FROM -f.imponibile OR NEW.categoria_id IS DISTINCT FROM f.categoria_id OR jsonb_array_length(NEW.quote)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(NEW.quote) q WHERE (q->>'importo') IS NULL OR (q->>'importo')::numeric>0) OR (SELECT sum((q->>'importo')::numeric) FROM jsonb_array_elements(NEW.quote) q) IS DISTINCT FROM NEW.importo THEN RAISE EXCEPTION 'Importo o quote dello storno non coerenti con la nota di credito.'; END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER nexus_fattura_riferimento BEFORE INSERT OR UPDATE ON public."AmministrativoFatture" FOR EACH ROW EXECUTE FUNCTION public.nexus_verifica_nota_credito();
CREATE TRIGGER nexus_movimento_storno BEFORE INSERT OR UPDATE ON public."AmministrativoMovimenti" FOR EACH ROW EXECUTE FUNCTION public.nexus_verifica_nota_credito();
CREATE FUNCTION public.nexus_salva_nota_credito(p_id uuid,p_dati jsonb,p_registra boolean,p_expected timestamptz) RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE f public."AmministrativoFatture"; amount numeric; cat uuid; ref uuid; start_month text; months integer; cents bigint; quotes jsonb; mid uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public."NexusProfili" WHERE "UserID"=auth.uid() AND "Attivo"=true AND "Ruolo" IN ('admin','amministrazione')) THEN RAISE EXCEPTION 'Accesso non autorizzato'; END IF;
 SELECT * INTO f FROM public."AmministrativoFatture" WHERE id=p_id FOR UPDATE;
 IF f.id IS NULL OR NOT public.nexus_tipo_nota_credito(f.tipo_documento) THEN RAISE EXCEPTION 'Nota di credito non trovata'; END IF;
 IF f.aggiornato_il IS DISTINCT FROM p_expected THEN RAISE EXCEPTION 'Documento aggiornato da un altro utente. Ricarica la pagina.'; END IF;
 ref=nullif(p_dati->>'fattura_riferimento_id','')::uuid;
 -- L’archivio storico consente soltanto il collegamento, senza nuove quote.
 IF f.data_documento < date '2026-09-01' THEN
  IF p_registra THEN RAISE EXCEPTION 'Il bilancino storico non può essere modificato.'; END IF;
  UPDATE public."AmministrativoFatture" SET fattura_riferimento_id=ref,aggiornato_il=clock_timestamp() WHERE id=p_id;
  RETURN p_id;
 END IF;
 amount=(p_dati->>'imponibile')::numeric; cat=nullif(p_dati->>'categoria_id','')::uuid; start_month=p_dati->>'mese_competenza'; months=(p_dati->>'durata_mesi')::integer;
 IF amount IS NULL OR amount<=0 OR amount::text IN ('NaN','Infinity','-Infinity') OR amount<>round(amount,2) OR start_month IS NULL OR start_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR start_month<'2026-09' OR months IS NULL OR months NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Controlla imponibile, mese e durata.'; END IF;
 IF f.movimento_id IS NOT NULL AND NOT p_registra THEN RAISE EXCEPTION 'Usa Aggiorna ripartizione per una nota già registrata.'; END IF;
 IF p_registra AND (ref IS NULL OR NOT EXISTS(SELECT 1 FROM public."AmministrativoCategorie" WHERE id=cat AND tipo='costo')) THEN RAISE EXCEPTION 'Scegli la fattura di riferimento e la categoria di spesa.'; END IF;
 UPDATE public."AmministrativoFatture" SET imponibile=amount,categoria_id=cat,fattura_riferimento_id=ref,mese_competenza=start_month,durata_mesi=months,modalita_pagamento=nullif(p_dati->>'modalita_pagamento',''),scadenza_pagamento=nullif(p_dati->>'scadenza_pagamento','')::date,note=nullif(p_dati->>'note',''),includi_bilancino=true,aggiornato_il=clock_timestamp() WHERE id=p_id;
 IF p_registra THEN
  cents=(amount*100)::bigint;
  SELECT jsonb_agg(jsonb_build_object('mese',to_char((start_month||'-01')::date+make_interval(months=>i),'YYYY-MM'),'importo',-(cents/months+CASE WHEN i<cents%months THEN 1 ELSE 0 END)/100.0) ORDER BY i) INTO quotes FROM generate_series(0,months-1) i;
  INSERT INTO public."AmministrativoMovimenti"(fattura_id,storno,tipo,categoria_id,descrizione,importo,data_documento,fornitore,riferimento,note,quote,includi_bilancino)
  VALUES(p_id,true,'costo',cat,left('Nota di credito '||f.numero||' · '||f.fornitore,250),-amount,f.data_documento,f.fornitore,f.numero,nullif(p_dati->>'note',''),quotes,true)
  ON CONFLICT(fattura_id) DO UPDATE SET storno=true,tipo='costo',categoria_id=EXCLUDED.categoria_id,descrizione=EXCLUDED.descrizione,importo=EXCLUDED.importo,note=EXCLUDED.note,quote=EXCLUDED.quote,includi_bilancino=true,annullato=false,aggiornato_il=clock_timestamp() RETURNING id INTO mid;
  UPDATE public."AmministrativoFatture" SET movimento_id=mid WHERE id=p_id;
 END IF;
 RETURN p_id;
END $$;
REVOKE ALL ON FUNCTION public.nexus_tipo_nota_credito(text),public.nexus_verifica_nota_credito(),public.nexus_salva_nota_credito(uuid,jsonb,boolean,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.nexus_tipo_nota_credito(text),public.nexus_salva_nota_credito(uuid,jsonb,boolean,timestamptz) TO authenticated;
