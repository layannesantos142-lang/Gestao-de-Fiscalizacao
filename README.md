# Fiscalização +

App de gestão das fiscalizações recebidas pela Ferreira Costa — Compliance | Governança Corporativa.

> **Status:** app conectado ao banco de dados (Supabase, projeto `Gestao de Fiscalizacao`, região São Paulo), com login por e-mail, regras de acesso por perfil e atualização em tempo real. Próximas etapas: anexos, avisos de prazo por e-mail e hospedagem.

## Banco de dados

- Estrutura completa em [`supabase/schema.sql`](supabase/schema.sql): tabelas `chamados`, `eventos` (histórico), `retornos`, `liberacoes`, `multas_lojista`, `perfis` (usuários), `filiais` e `listas` (órgãos, motivos, não conformidades).
- Regras de acesso (RLS): a **Filial** vê só os chamados da própria filial; **Jurídico** e **Compliance** veem todos; só o **Compliance** altera cadastros e perfis e decide liberações.
- `config.js` guarda o endereço do projeto e a chave **publicável** (feita para o navegador). Nunca colocar a chave secreta no repositório.
- **Login por filial + setor** (não por pessoa): na entrada, escolhe-se a filial, o setor e digita-se a senha. Cada conta usa um e-mail interno `filial.setor@fiscalizacao.fc`.
- **Contas criadas só pelo Compliance**, na tela **Contas de acesso** do app (função `supabase/functions/gerenciar-usuarios`). Ao criar, o Compliance define o perfil (Filial, Jurídico ou Compliance) e **quais filiais a conta pode visualizar** — regra aplicada no próprio banco (`ve_filial`).
- A primeira conta criada no painel do Supabase (`corp.compliance@fiscalizacao.fc`) vira **CORP · Compliance** automaticamente.
- **Manter ativo:** `.github/workflows/manter-ativo.yml` chama a função `manter_ativo` 2x por dia, para o plano gratuito do Supabase não pausar após 7 dias sem uso.

## Objetivo

Garantir que toda fiscalização seja acompanhada pelas pessoas certas, registrada no mesmo dia e tratada dentro do prazo definido pelo órgão — preservando o histórico de cada caso, evitando perda de prazos e reduzindo o risco de multas, interdições e ações judiciais.

## Perfis

| Perfil | Papel |
|---|---|
| **Filial (ADM)** | Abre o chamado no mesmo dia da fiscalização (Loja, Loja do Mall, CD ou Obra) e responde às solicitações do Jurídico |
| **Jurídico** | Atende os chamados: analisa, solicita documentos à filial, responde ao órgão e registra o desfecho |
| **Compliance** | Cria e mantém o app, monitora os indicadores e pode pontuar, editar ou reabrir qualquer chamado |

## Regras de negócio

- **Prazo do órgão** é obrigatório quando há notificação e orienta todos os prazos internos.
- **Retorno entre setores:** cada envio Filial ↔ Jurídico tem prazo de retorno (padrão 2 dias), nunca depois da véspera do prazo do órgão.
- **Limite de envios:** até 2 envios por setor. Depois disso, só com liberação do Compliance (+2 por liberação).
- **Loja do Mall:** o lojista responde pela própria fiscalização; a filial pode propor multa contratual por certificado/licença vencida, e o **Jurídico confirma** aplicação e valor (cláusulas 22.2 e 22.3).
- **Obra:** registrar obra/empreiteira e responsável técnico (ART/RRT).

## Foco do monitoramento (painel do Compliance)

1. Quais órgãos fizeram apreensão
2. Quais emitiram notificação
3. Quais fizeram visita sem notificação
4. Com que frequência cada órgão visitou as filiais
5. Quais não conformidades foram mais apontadas
6. Quais órgãos aplicaram multa e por qual motivo

## Estrutura

```
index.html          App (3 perfis, conectado ao Supabase; o config.js é embutido na geração)
config.js           Endereço do projeto + chave publicável do Supabase
supabase/schema.sql Estrutura do banco e regras de acesso
supabase/02_login_filial_setor.sql  Login por filial+setor e filtro de visualização
supabase/functions/gerenciar-usuarios  Criação de contas (só Compliance)
.github/workflows/manter-ativo.yml     Mantém o Supabase ativo
docs/sintese.html   Síntese executiva do processo
```

## Cronograma

| Etapa | Previsão |
|---|---|
| Validação jurídica do POP | até 09/10 |
| POP Jurídico | até 15/10 |
| Dados das áreas faltantes (DP/RH, Mall) | até 21/10 |
| Início do projeto do app | até 23/10 |
| App em funcionamento | 19/11 |

## Próximos passos técnicos

1. ~~Banco de dados~~ ✅
2. ~~Login por perfil, regras de acesso e tempo real~~ ✅
3. Anexos (notificação, fotos, auto de apreensão) — Supabase Storage
4. Avisos de prazo por e-mail
5. Hospedagem (link para as filiais) e keep-alive do projeto gratuito

---
Uso interno · Confidencial
