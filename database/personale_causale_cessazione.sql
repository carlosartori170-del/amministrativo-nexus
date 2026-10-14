ALTER TABLE public."AmministrativoDatiPersonale" ADD COLUMN causale_cessazione text;
COMMENT ON COLUMN public."AmministrativoDatiPersonale".causale_cessazione IS 'Nota facoltativa inserita alla cessazione del rapporto di lavoro amministrativo.';
