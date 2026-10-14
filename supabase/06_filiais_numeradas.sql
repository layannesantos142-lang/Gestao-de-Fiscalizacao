-- =====================================================================
-- Fiscalização + — Filiais pela numeração da Ferreira Costa
-- (rodar depois do 05_anexos_e_responsavel.sql)
-- Nada é apagado: os códigos antigos (siglas) ficam inativos e os dados passam para o número novo.
-- =====================================================================
alter table public.filiais add column if not exists loja boolean not null default true;

insert into public.filiais (codigo, nome, loja, ativa) values
  ('1','Garanhuns',true,true), ('2','Imbiribeira',true,true), ('3','Paralela',true,true),
  ('4','Tamarineira',true,true), ('5','Aracaju',true,true), ('6','João Pessoa',true,true),
  ('7','Natal',true,true), ('8','Caruaru',true,true), ('9','Barris',true,true),
  ('92','Cabo',true,true), ('93','Alhandra',true,true), ('94','Lauro de Freitas',true,true),
  ('99','Corporativo',false,true)
on conflict (codigo) do update set nome = excluded.nome, loja = excluded.loja, ativa = true;

-- de-para das siglas antigas
update public.chamados c set filial = d.novo
  from (values ('GUS','1'),('IMB','2'),('PAL','3'),('JPA','6'),('CAU','8'),('BAR','9'),('CORP','99')) d(velho, novo)
  where c.filial = d.velho;
update public.perfis p set filial = d.novo
  from (values ('GUS','1'),('IMB','2'),('PAL','3'),('JPA','6'),('CAU','8'),('BAR','9'),('CORP','99')) d(velho, novo)
  where p.filial = d.velho;
update public.perfis p set filiais_visiveis = (
    select array_agg(coalesce(d.novo, f) order by f) from unnest(p.filiais_visiveis) f
    left join (values ('GUS','1'),('IMB','2'),('PAL','3'),('JPA','6'),('CAU','8'),('BAR','9'),('CORP','99')) d(velho, novo) on d.velho = f)
  where p.filiais_visiveis is not null and array_length(p.filiais_visiveis, 1) > 0;

-- siglas antigas ficam inativas (não aparecem mais), mas não são apagadas
update public.filiais set ativa = false
  where codigo in ('GUS','IMB','PAL','JPA','CAU','BAR','CORP','REC','PNG');

-- a primeira conta (administradora) passa a nascer na filial 99 · Corporativo
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean := not exists (select 1 from public.perfis where papel = 'compliance');
begin
  insert into public.perfis (id, email, nome, papel, filial, setor)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'nome', case when primeiro then 'Compliance' else split_part(new.email,'@',1) end),
          case when primeiro then 'compliance' else 'pendente' end,
          case when primeiro then '99' else null end,
          case when primeiro then 'Compliance' else 'Administrativo' end)
  on conflict (id) do nothing;
  return new;
end $$;
