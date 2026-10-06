/* =============================================================================
   BARRAGENS DE USINAS HIDRELÉTRICAS (ANA / SNISB) - SCRIPT 03: VALIDAÇÃO
   -----------------------------------------------------------------------------
   Opcional. Prova que o modelo normalizado guarda TODA a informação do CSV:
   reconstrói as 33 colunas pela visão vw_barragem_csv e compara, linha a linha
   e coluna a coluna, com a cópia fiel do CSV no schema staging.
   Resultado esperado: 0 diferenças nos dois sentidos.

   No pgAdmin só aparece o resultado da ÚLTIMA consulta: ela é um resumo com
   todas as verificações (coluna ok = true em todas as linhas). Para ver as
   consultas detalhadas, selecione cada uma e execute só a seleção (F5).
   ============================================================================= */

-- Projeção tipada do CSV original (vazio -> NULL)
CREATE OR REPLACE TEMP VIEW tmp_csv_tipado AS
SELECT
    cod_snisb::integer                          AS cod_snisb,
    cod_fiscalizador::integer                   AS cod_fiscalizador,
    nome,
    altura_fundacao_m::numeric                  AS altura_fundacao_m,
    NULLIF(altura_terreno_m,'')::numeric        AS altura_terreno_m,
    capacidade_reservatorio::numeric            AS capacidade_reservatorio,
    data_cadastro::date                         AS data_cadastro,
    NULLIF(tipo_material,'')                    AS tipo_material,
    uso_principal,
    latitude::numeric                           AS latitude,
    longitude::numeric                          AS longitude,
    regulada_pnsb::boolean                      AS regulada_pnsb,
    empreendedor,
    uf,
    upper(municipio)                            AS municipio,   -- ver nota sobre grafias
    NULLIF(fase_vida,'')                        AS fase_vida,
    orgao_fiscalizador,
    numero_autorizacao,
    NULLIF(data_autorizacao,'')::date           AS data_autorizacao,
    regiao_hidrografica,
    NULLIF(cod_trecho_curso_dagua,'')           AS cod_trecho_curso_dagua,
    curso_dagua,
    NULLIF(dominio_curso_dagua,'')              AS dominio_curso_dagua,
    NULLIF(comite_federal,'')                   AS comite_federal,
    NULLIF(comite_estadual,'')                  AS comite_estadual,
    NULLIF(unidade_gestao,'')                   AS unidade_gestao,
    NULLIF(possui_pae,'')::boolean              AS possui_pae,
    possui_plano_seguranca::boolean             AS possui_plano_seguranca,
    possui_revisao_periodica::boolean           AS possui_revisao_periodica,
    categoria_risco,
    dano_potencial_associado,
    barragem_autuada::boolean                   AS barragem_autuada,
    completude_cadastro
FROM staging.csv_barragens;

CREATE OR REPLACE TEMP VIEW tmp_banco AS
SELECT cod_snisb, cod_fiscalizador, nome, altura_fundacao_m, altura_terreno_m,
       capacidade_reservatorio, data_cadastro, tipo_material, uso_principal,
       latitude, longitude, regulada_pnsb, empreendedor, uf,
       upper(municipio) AS municipio,
       fase_vida, orgao_fiscalizador, numero_autorizacao, data_autorizacao,
       regiao_hidrografica, cod_trecho_curso_dagua, curso_dagua,
       dominio_curso_dagua, comite_federal, comite_estadual, unidade_gestao,
       possui_pae, possui_plano_seguranca, possui_revisao_periodica,
       categoria_risco, dano_potencial_associado, barragem_autuada,
       completude_cadastro
FROM vw_barragem_csv;

-- == 1. Quantidade de linhas (esperado: 887 e 887) ==
SELECT (SELECT count(*) FROM staging.csv_barragens) AS linhas_csv,
       (SELECT count(*) FROM barragem)              AS linhas_banco;

-- == 2. Linhas do CSV que o banco NÃO reproduz (esperado: 0) ==
SELECT count(*) AS diferencas_csv_menos_banco
FROM (SELECT * FROM tmp_csv_tipado EXCEPT ALL SELECT * FROM tmp_banco) d;

-- == 3. Linhas do banco que NÃO existem no CSV (esperado: 0) ==
SELECT count(*) AS diferencas_banco_menos_csv
FROM (SELECT * FROM tmp_banco EXCEPT ALL SELECT * FROM tmp_csv_tipado) d;

-- == 4. Grafia de município unificada (única diferença, só de maiúsculas/minúsculas) ==
SELECT s.cod_snisb, s.municipio AS grafia_no_csv, m.nome AS grafia_no_banco, m.sigla_uf
FROM staging.csv_barragens s
JOIN barragem  b ON b.cod_snisb = s.cod_snisb::integer
JOIN municipio m ON m.id_municipio = b.id_municipio
WHERE s.municipio <> m.nome
ORDER BY m.nome;

-- == 5. Integridade: unidade_gestao = COALESCE(comite_federal, comite_estadual) em 100% das linhas ==
SELECT count(*) FILTER (WHERE NULLIF(unidade_gestao,'') IS NOT DISTINCT FROM
                              COALESCE(NULLIF(comite_federal,''), NULLIF(comite_estadual,''))) AS linhas_ok,
       count(*) AS total
FROM staging.csv_barragens;

-- == 6. Diagnóstico da capacidade do reservatório ==
SELECT b.cod_tratamento_capacidade, count(*) AS barragens,
       min(b.capacidade_reservatorio) AS menor_valor_fonte,
       max(b.capacidade_reservatorio) AS maior_valor_fonte
FROM barragem b
GROUP BY 1
ORDER BY 2 DESC;

-- == 7. Barragens com capacidade corrigida ou suspeita ==
SELECT cod_snisb, nome, altura_fundacao_m, capacidade_reservatorio AS valor_fonte,
       cod_tratamento_capacidade, capacidade_hm3
FROM vw_barragem
WHERE cod_tratamento_capacidade <> 'CONSISTENTE'
ORDER BY capacidade_reservatorio DESC;

-- == RESUMO (última consulta: é a que o pgAdmin mostra) ==
SELECT 'Linhas no CSV = linhas no banco (887)' AS verificacao,
       (SELECT count(*) FROM staging.csv_barragens)::text || ' / ' || (SELECT count(*) FROM barragem)::text AS resultado,
       (SELECT count(*) FROM staging.csv_barragens) = 887 AND (SELECT count(*) FROM barragem) = 887 AS ok
UNION ALL
SELECT 'Linhas do CSV que o banco não reproduz',
       (SELECT count(*) FROM (SELECT * FROM tmp_csv_tipado EXCEPT ALL SELECT * FROM tmp_banco) d)::text,
       (SELECT count(*) FROM (SELECT * FROM tmp_csv_tipado EXCEPT ALL SELECT * FROM tmp_banco) d) = 0
UNION ALL
SELECT 'Linhas do banco que não existem no CSV',
       (SELECT count(*) FROM (SELECT * FROM tmp_banco EXCEPT ALL SELECT * FROM tmp_csv_tipado) d)::text,
       (SELECT count(*) FROM (SELECT * FROM tmp_banco EXCEPT ALL SELECT * FROM tmp_csv_tipado) d) = 0
UNION ALL
SELECT 'Barragens com capacidade tratada (não consistente)',
       (SELECT count(*) FROM barragem WHERE cod_tratamento_capacidade <> 'CONSISTENTE')::text,
       (SELECT count(*) FROM barragem WHERE cod_tratamento_capacidade <> 'CONSISTENTE') = 16;
