-- =====================================================================
-- Fiscalização + — Login por FILIAL + SETOR e filtro de visualização por conta
-- (rodar depois do schema.sql)
-- =====================================================================

-- Filiais: "loja" = aparece nos chamados; CORP = corporativo (contas do Jurídico/Compliance)
alter table public.filiais add column if not exists loja boolean not null default true;
insert into public.filiais (codigo, nome, loja) values ('CORP', 'Corporativo', false)
  on conflict (codigo) do update set loja = false, nome = 'Corporativo';

-- Setores (lista mantida pelo Compliance)
alter table public.listas drop constraint if exists listas_tipo_check;
alter table public.listas add constraint listas_tipo_check check (tipo in ('orgao','nc','motivo','setor'));
insert into public.listas (tipo, valor, ordem) values
  ('setor','Administrativo',1),('setor','Gerência',2),('setor','Prevenção',3),('setor','RH / DP',4),
  ('setor','Jurídico',5),('setor','Compliance',6)
  on conflict do nothing;

-- O que cada conta pode visualizar: lista de filiais (vazio = padrão do perfil)
--   Filial: padrão = só a própria filial | Jurídico/Compliance: padrão = todas
alter table public.perfis add column if not exists filiais_visiveis text[];

create or replace function public.ve_filial(f text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.perfis p
    where p.id = auth.uid() and p.ativo and p.papel <> 'pendente'
      and ( p.filial = f
            or (coalesce(array_length(p.filiais_visiveis,1),0) = 0 and p.papel in ('juridico','compliance'))
            or f = any(p.filiais_visiveis) )
  )
$$;

create or replace function public.pode_ver(cid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chamados c where c.id = cid and public.ve_filial(c.filial))
$$;

drop policy if exists chamados_ler on public.chamados;
create policy chamados_ler on public.chamados for select to authenticated using (public.ve_filial(filial));
drop policy if exists chamados_criar on public.chamados;
create policy chamados_criar on public.chamados for insert to authenticated
  with check ( public.meu_papel() = 'compliance'
               or (public.meu_papel() = 'filial' and filial = public.minha_filial()) );
drop policy if exists chamados_alterar on public.chamados;
create policy chamados_alterar on public.chamados for update to authenticated
  using (public.ve_filial(filial)) with check (public.ve_filial(filial));

-- A PRIMEIRA conta criada vira CORP · Compliance (administradora); as demais são criadas pelo Compliance no app
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean := not exists (select 1 from public.perfis where papel = 'compliance');
begin
  insert into public.perfis (id, email, nome, papel, filial, setor)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'nome', case when primeiro then 'CORP · Compliance' else split_part(new.email,'@',1) end),
          case when primeiro then 'compliance' else 'pendente' end,
          case when primeiro then 'CORP' else null end,
          case when primeiro then 'Compliance' else 'Administrativo' end)
  on conflict (id) do nothing;
  return new;
end $$;

-- A tela de login precisa listar filiais e setores antes de entrar (dados não sensíveis)
drop policy if exists filiais_login on public.filiais;
create policy filiais_login on public.filiais for select to anon using (ativa);
drop policy if exists setores_login on public.listas;
create policy setores_login on public.listas for select to anon using (tipo = 'setor');
