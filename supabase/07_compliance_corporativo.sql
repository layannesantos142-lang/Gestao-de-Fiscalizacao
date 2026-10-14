-- =====================================================================
-- Fiscalização + — Quem é Compliance entra sempre como 99 · Corporativo (setor Compliance)
-- (rodar depois do 06_filiais_numeradas.sql)
-- =====================================================================
create or replace function public.compliance_corporativo() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.papel = 'compliance' then
    new.filial := '99';
    new.setor  := 'Compliance';
  end if;
  return new;
end $$;

drop trigger if exists perfis_compliance_corporativo on public.perfis;
create trigger perfis_compliance_corporativo before insert or update on public.perfis
  for each row execute function public.compliance_corporativo();

-- ajusta quem já é Compliance
update public.perfis set filial = '99', setor = 'Compliance'
  where papel = 'compliance' and (filial is distinct from '99' or setor is distinct from 'Compliance');
