# Fiscalização +

App de gestão das fiscalizações recebidas pela Ferreira Costa — Compliance | Governança Corporativa.

> **Status:** esboço navegável (dados fictícios, nada é salvo). Próxima etapa: conectar a um banco de dados.

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
index.html        App (esboço navegável, 3 perfis)
docs/sintese.html Síntese executiva do processo
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

1. Banco de dados (tabelas: chamados, histórico, retornos, liberações, multas a lojistas, cadastros, usuários)
2. Login por perfil e regras de acesso (filial vê só os próprios chamados — LGPD)
3. Anexos (notificação, fotos, auto de apreensão)
4. Avisos de prazo por e-mail

---
Uso interno · Confidencial
