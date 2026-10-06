/* =============================================================================
   BARRAGENS DE USINAS HIDRELÉTRICAS (ANA / SNISB) - SCRIPT 01: DDL
   -----------------------------------------------------------------------------
   Equipe:
     - Eduardo Aragão Rodrigues
     - Douglas Daibes
     - Marcos Costa

   SGBD ....: PostgreSQL 13+ (testado no PostgreSQL 16)
   Execução : psql -d <banco_vazio> -f 01_ddl.sql
   Ordem ...: 01_ddl.sql -> 02_carga.sql -> 03_validacao.sql (opcional)

   Modelo normalizado até a 3ª Forma Normal a partir de ana_barragens_hidreletricas.csv
   (887 barragens x 33 colunas). As decisões de modelagem estão no README.md e
   no documento de modelagem.
   ============================================================================= */

SET client_encoding = 'UTF8';

-- Permite reexecutar o script sem erro (em banco vazio estes comandos não fazem nada)
DROP VIEW  IF EXISTS vw_barragem_csv       CASCADE;
DROP VIEW  IF EXISTS vw_barragem           CASCADE;
DROP TABLE IF EXISTS barragem              CASCADE;
DROP TABLE IF EXISTS tratamento_capacidade CASCADE;
DROP TABLE IF EXISTS fase_vida             CASCADE;
DROP TABLE IF EXISTS material_construcao   CASCADE;
DROP TABLE IF EXISTS uso_principal         CASCADE;
DROP TABLE IF EXISTS orgao_fiscalizador    CASCADE;
DROP TABLE IF EXISTS empreendedor          CASCADE;
DROP TABLE IF EXISTS comite_bacia_estadual CASCADE;
DROP TABLE IF EXISTS comite_bacia_federal  CASCADE;
DROP TABLE IF EXISTS curso_dagua           CASCADE;
DROP TABLE IF EXISTS municipio             CASCADE;
DROP TABLE IF EXISTS uf                    CASCADE;
DROP TABLE IF EXISTS regiao_hidrografica   CASCADE;


/* =============================================================================
   1. LOCALIZAÇÃO POLÍTICO-ADMINISTRATIVA:  UF  1 ──< N  MUNICÍPIO
   ============================================================================= */

CREATE TABLE uf (
    sigla  CHAR(2)      PRIMARY KEY,
    nome   VARCHAR(30)  NOT NULL UNIQUE,
    CONSTRAINT ck_uf_sigla CHECK (sigla ~ '^[A-Z]{2}$')
);
COMMENT ON TABLE  uf       IS 'Unidades da Federação (tabela de referência com as 27 UFs; o CSV usa 22).';
COMMENT ON COLUMN uf.sigla IS 'Sigla da UF (coluna uf do CSV).';

CREATE TABLE municipio (
    id_municipio INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(60)  NOT NULL,
    sigla_uf CHAR(2)  NOT NULL REFERENCES uf (sigla),
    CONSTRAINT uq_municipio_nome_uf UNIQUE (nome, sigla_uf),
    CONSTRAINT ck_municipio_nome    CHECK (btrim(nome) <> '')
);

-- Nome de município não é único no país (ex.: GUARACIABA existe em SC e MG):
-- a chave natural é (nome, UF). O índice abaixo impede o mesmo município
-- cadastrado duas vezes com grafias que só diferem em maiúsculas/minúsculas.
CREATE UNIQUE INDEX uq_municipio_nome_upper_uf ON municipio (upper(nome), sigla_uf);
CREATE INDEX ix_municipio_uf ON municipio (sigla_uf);
COMMENT ON TABLE municipio IS 'Municípios onde há barragens. Chave natural: (nome, sigla_uf).';


/* =============================================================================
   2. HIDROGRAFIA:  REGIÃO HIDROGRÁFICA 1 ──< N CURSO D'ÁGUA
                    COMITÊS DE BACIA (federal e estadual)
   ============================================================================= */

CREATE TABLE regiao_hidrografica (
    id_regiao SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(60) NOT NULL UNIQUE,
    CONSTRAINT ck_regiao_nome CHECK (btrim(nome) <> '')
);

COMMENT ON TABLE regiao_hidrografica IS 'Regiões Hidrográficas (CNRH 32/2003) presentes no CSV (11 das 12).';

CREATE TABLE curso_dagua (
    id_curso_dagua INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    id_regiao SMALLINT NOT NULL REFERENCES regiao_hidrografica (id_regiao),
    CONSTRAINT uq_curso_dagua_nome_regiao UNIQUE (nome, id_regiao),
    CONSTRAINT ck_curso_dagua_nome CHECK (btrim(nome) <> '')
);
CREATE INDEX ix_curso_dagua_regiao ON curso_dagua (id_regiao);
COMMENT ON TABLE  curso_dagua      IS 'Rio/córrego barrado. Nomes se repetem entre regiões (ex.: "Rio Grande"), por isso a chave natural é (nome, região).';
COMMENT ON COLUMN curso_dagua.nome IS '"SEM NOME" é mantido como está na fonte (curso d''água não nomeado).';

CREATE TABLE comite_bacia_federal (
    id_comite_federal  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    CONSTRAINT ck_comite_federal_nome CHECK (btrim(nome) <> '')
);
COMMENT ON TABLE comite_bacia_federal IS 'Comitês de bacia hidrográfica de rios de domínio da União.';

CREATE TABLE comite_bacia_estadual (
    id_comite_estadual SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    CONSTRAINT ck_comite_estadual_nome CHECK (btrim(nome) <> '')
);
COMMENT ON TABLE comite_bacia_estadual IS 'Comitês de bacia hidrográfica estaduais.';


/* =============================================================================
   3. AGENTES E DOMÍNIOS (tabelas de apoio / lookup)
   ============================================================================= */

CREATE TABLE empreendedor (
    id_empreendedor INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(120) NOT NULL UNIQUE,
    CONSTRAINT ck_empreendedor_nome CHECK (btrim(nome) <> '')
);
COMMENT ON TABLE empreendedor IS 'Empreendedor (pessoa física ou jurídica) responsável legal pela barragem.';

CREATE TABLE orgao_fiscalizador (
    id_orgao_fiscalizador  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    CONSTRAINT ck_orgao_nome CHECK (btrim(nome) <> '')
);
COMMENT ON TABLE orgao_fiscalizador IS 'Órgão fiscalizador. Coluna constante no CSV (ANEEL), mantida como entidade: no SNISB há outros fiscalizadores (ANA, ANM, órgãos estaduais) e o cod_fiscalizador só é único dentro de cada órgão.';

CREATE TABLE uso_principal (
    id_uso_principal SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descricao VARCHAR(40) NOT NULL UNIQUE,
    CONSTRAINT ck_uso_descricao CHECK (btrim(descricao) <> '')
);
COMMENT ON TABLE uso_principal IS 'Uso principal do barramento. Constante no CSV (Hidroelétrica), mantido como domínio: o SNISB também cadastra irrigação, abastecimento, etc.';

CREATE TABLE material_construcao (
    id_material SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descricao VARCHAR(40) NOT NULL UNIQUE,
    CONSTRAINT ck_material_descricao CHECK (btrim(descricao) <> '')
);
COMMENT ON TABLE material_construcao IS 'Tipo de material da barragem. "Sem Informação" é um valor da fonte e é diferente de NULL (campo vazio no CSV).';

CREATE TABLE fase_vida (
    id_fase_vida  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descricao VARCHAR(30) NOT NULL UNIQUE,
    CONSTRAINT ck_fase_descricao CHECK (btrim(descricao) <> '')
);
COMMENT ON TABLE fase_vida IS 'Fase de vida da barragem (Projeto, Construção, 1º enchimento, Operação, Desativada).';

CREATE TABLE tratamento_capacidade (
    cod_tratamento  VARCHAR(20) PRIMARY KEY,
    descricao VARCHAR(250) NOT NULL,
    fator_para_hm3  NUMERIC(12,9),
    CONSTRAINT ck_tratamento_cod   CHECK (cod_tratamento ~ '^[A-Z0-9_]+$'),
    CONSTRAINT ck_tratamento_fator CHECK (fator_para_hm3 IS NULL OR fator_para_hm3 > 0)
);
COMMENT ON TABLE  tratamento_capacidade IS 'Classificação da inconsistência de unidade da capacidade do reservatório e fator para converter o valor da fonte em hm³.';
COMMENT ON COLUMN tratamento_capacidade.fator_para_hm3 IS 'capacidade_hm3 = capacidade_reservatorio * fator. NULL = valor não confiável, sem conversão segura.';


/* =============================================================================
   4. ENTIDADE CENTRAL: BARRAGEM
   ============================================================================= */

CREATE TABLE barragem (
    -- identificação
    cod_snisb                 INTEGER       PRIMARY KEY,
    id_orgao_fiscalizador     SMALLINT      NOT NULL REFERENCES orgao_fiscalizador (id_orgao_fiscalizador),
    cod_fiscalizador          INTEGER       NOT NULL,
    nome                      VARCHAR(120)  NOT NULL,
    data_cadastro             DATE          NOT NULL,
    id_empreendedor           INTEGER       NOT NULL REFERENCES empreendedor (id_empreendedor),

    -- características físicas
    altura_fundacao_m         NUMERIC(7,2)  NOT NULL,
    altura_terreno_m          NUMERIC(7,2),
    capacidade_reservatorio   NUMERIC(16,3) NOT NULL,
    cod_tratamento_capacidade VARCHAR(20)   NOT NULL REFERENCES tratamento_capacidade (cod_tratamento),
    id_material               SMALLINT      REFERENCES material_construcao (id_material),
    id_uso_principal          SMALLINT      NOT NULL REFERENCES uso_principal (id_uso_principal),
    id_fase_vida              SMALLINT      REFERENCES fase_vida (id_fase_vida),

    -- localização
    latitude                  NUMERIC(7,4)  NOT NULL,
    longitude                 NUMERIC(7,4)  NOT NULL,
    id_municipio              INTEGER       NOT NULL REFERENCES municipio (id_municipio),

    -- hidrografia
    id_curso_dagua            INTEGER       NOT NULL REFERENCES curso_dagua (id_curso_dagua),
    cod_trecho_curso_dagua    VARCHAR(15),
    dominio_curso_dagua       VARCHAR(10),
    id_comite_federal         SMALLINT      REFERENCES comite_bacia_federal (id_comite_federal),
    id_comite_estadual        SMALLINT      REFERENCES comite_bacia_estadual (id_comite_estadual),

    -- autorização de operação
    numero_autorizacao        VARCHAR(30)   NOT NULL,
    data_autorizacao          DATE,

    -- segurança da barragem (Lei 12.334/2010 - PNSB)
    regulada_pnsb             BOOLEAN       NOT NULL,
    possui_pae                BOOLEAN,
    possui_plano_seguranca    BOOLEAN       NOT NULL,
    possui_revisao_periodica  BOOLEAN       NOT NULL,
    categoria_risco           VARCHAR(5)    NOT NULL,
    dano_potencial_associado  VARCHAR(5)    NOT NULL,
    barragem_autuada          BOOLEAN       NOT NULL,
    completude_cadastro       VARCHAR(20)   NOT NULL,

    CONSTRAINT uq_barragem_orgao_cod_fiscalizador UNIQUE (id_orgao_fiscalizador, cod_fiscalizador),
    CONSTRAINT ck_barragem_cod_snisb       CHECK (cod_snisb > 0),
    CONSTRAINT ck_barragem_cod_fiscal      CHECK (cod_fiscalizador > 0),
    CONSTRAINT ck_barragem_nome            CHECK (btrim(nome) <> ''),
    CONSTRAINT ck_barragem_altura_fundacao CHECK (altura_fundacao_m >= 0),
    CONSTRAINT ck_barragem_altura_terreno  CHECK (altura_terreno_m IS NULL OR altura_terreno_m >= 0),
    CONSTRAINT ck_barragem_capacidade      CHECK (capacidade_reservatorio >= 0),
	
    -- envelope geográfico do território brasileiro
	
    CONSTRAINT ck_barragem_latitude        CHECK (latitude  BETWEEN -34.0 AND 5.5),
    CONSTRAINT ck_barragem_longitude       CHECK (longitude BETWEEN -74.0 AND -28.5),
    CONSTRAINT ck_barragem_cod_trecho      CHECK (cod_trecho_curso_dagua ~ '^[0-9]+$'),
    CONSTRAINT ck_barragem_dominio         CHECK (dominio_curso_dagua IN ('Federal', 'Estadual')),
    CONSTRAINT ck_barragem_num_autorizacao CHECK (btrim(numero_autorizacao) <> ''),
    CONSTRAINT ck_barragem_datas           CHECK (data_cadastro >= DATE '1900-01-01'
                                                  AND (data_autorizacao IS NULL OR data_autorizacao >= DATE '1900-01-01')),
												  
    -- classificações da Lei 12.334/2010 (domínio fechado de 3 níveis)
	
    CONSTRAINT ck_barragem_categoria_risco CHECK (categoria_risco          IN ('Baixo', 'Médio', 'Alto')),
    CONSTRAINT ck_barragem_dano_potencial  CHECK (dano_potencial_associado IN ('Baixo', 'Médio', 'Alto')),
    CONSTRAINT ck_barragem_completude      CHECK (btrim(completude_cadastro) <> '')
);

-- Índices nas chaves estrangeiras (PostgreSQL não cria automaticamente) e nos filtros mais usados

CREATE INDEX ix_barragem_empreendedor   ON barragem (id_empreendedor);
CREATE INDEX ix_barragem_municipio      ON barragem (id_municipio);
CREATE INDEX ix_barragem_curso_dagua    ON barragem (id_curso_dagua);
CREATE INDEX ix_barragem_comite_federal ON barragem (id_comite_federal);
CREATE INDEX ix_barragem_comite_estad   ON barragem (id_comite_estadual);
CREATE INDEX ix_barragem_material       ON barragem (id_material);
CREATE INDEX ix_barragem_fase_vida      ON barragem (id_fase_vida);
CREATE INDEX ix_barragem_tratamento_cap ON barragem (cod_tratamento_capacidade);
CREATE INDEX ix_barragem_risco_dano     ON barragem (categoria_risco, dano_potencial_associado);
CREATE INDEX ix_barragem_nome           ON barragem (nome);

COMMENT ON TABLE  barragem IS 'Barragem de usina hidrelétrica submetida à PNSB (uma linha do CSV = uma barragem).';
COMMENT ON COLUMN barragem.capacidade_reservatorio   IS 'Valor EXATAMENTE como publicado pela fonte (unidade nominal hm³, mas com inconsistências). Ver cod_tratamento_capacidade e vw_barragem.capacidade_hm3.';
COMMENT ON COLUMN barragem.cod_tratamento_capacidade IS 'Diagnóstico da unidade do valor de capacidade (ver tabela tratamento_capacidade).';
COMMENT ON COLUMN barragem.cod_trecho_curso_dagua    IS 'Código do trecho de curso d''água (base hidrográfica ANA). Não identifica o rio: o mesmo código aparece com rios diferentes na fonte.';
COMMENT ON COLUMN barragem.dominio_curso_dagua       IS 'Domínio do curso d''água no trecho, como informado no cadastro (esparso e inconsistente por rio na fonte, por isso fica na barragem).';
COMMENT ON COLUMN barragem.numero_autorizacao        IS 'Número do ato de autorização. Não é identificador (ex.: "007" em 23 barragens com datas distintas).';
COMMENT ON COLUMN barragem.data_autorizacao          IS '2000-01-01 aparece em 211 linhas e provavelmente é data genérica da fonte; mantida sem alteração.';
COMMENT ON COLUMN barragem.regulada_pnsb             IS 'Constante (true) neste recorte; mantida por ser atributo de cada barragem no SNISB.';
COMMENT ON COLUMN barragem.barragem_autuada          IS 'Constante (false) neste recorte; mantida por ser situação que muda por barragem.';
COMMENT ON COLUMN barragem.completude_cadastro       IS 'Constante ("boa") neste recorte; mantida por ser avaliação de cada cadastro.';


/* =============================================================================
   5. VISÕES
   -----------------------------------------------------------------------------
   * unidade_gestao NÃO é armazenada: na fonte ela é sempre
         COALESCE(comite_federal, comite_estadual)
     (verificado nas 887 linhas). Armazená-la seria dependência transitiva
     (barragem -> comitês -> unidade_gestao). Ela é recalculada nas visões.
   * capacidade_hm3 é derivada (valor da fonte x fator), por isso também só
     existe na visão.
   ============================================================================= */

-- Visão analítica: tudo desnormalizado + colunas derivadas. Use nas consultas.
CREATE VIEW vw_barragem AS
SELECT
    b.cod_snisb,
    b.cod_fiscalizador,
    b.nome,
    substring(b.nome FROM '^(UHE|PCH|CGH)\s')       AS tipo_usina,
    b.altura_fundacao_m,
    b.altura_terreno_m,
    b.capacidade_reservatorio,
    b.cod_tratamento_capacidade,
    round(b.capacidade_reservatorio * tc.fator_para_hm3, 6) AS capacidade_hm3,
    b.data_cadastro,
    mc.descricao                                      AS tipo_material,
    up.descricao                                      AS uso_principal,
    b.latitude,
    b.longitude,
    b.regulada_pnsb,
    e.nome                                            AS empreendedor,
    m.sigla_uf                                        AS uf,
    u.nome                                            AS nome_uf,
    m.nome                                            AS municipio,
    fv.descricao                                      AS fase_vida,
    o.nome                                            AS orgao_fiscalizador,
    b.numero_autorizacao,
    b.data_autorizacao,
    rh.nome                                           AS regiao_hidrografica,
    b.cod_trecho_curso_dagua,
    cd.nome                                           AS curso_dagua,
    b.dominio_curso_dagua,
    cf.nome                                           AS comite_federal,
    ce.nome                                           AS comite_estadual,
    COALESCE(cf.nome, ce.nome)                        AS unidade_gestao,
    b.possui_pae,
    b.possui_plano_seguranca,
    b.possui_revisao_periodica,
    b.categoria_risco,
    b.dano_potencial_associado,
    b.barragem_autuada,
    b.completude_cadastro
FROM barragem b
JOIN empreendedor            e  ON e.id_empreendedor        = b.id_empreendedor
JOIN municipio               m  ON m.id_municipio           = b.id_municipio
JOIN uf                      u  ON u.sigla                  = m.sigla_uf
JOIN curso_dagua             cd ON cd.id_curso_dagua        = b.id_curso_dagua
JOIN regiao_hidrografica     rh ON rh.id_regiao             = cd.id_regiao
JOIN orgao_fiscalizador      o  ON o.id_orgao_fiscalizador  = b.id_orgao_fiscalizador
JOIN uso_principal           up ON up.id_uso_principal      = b.id_uso_principal
JOIN tratamento_capacidade   tc ON tc.cod_tratamento        = b.cod_tratamento_capacidade
LEFT JOIN material_construcao   mc ON mc.id_material        = b.id_material
LEFT JOIN fase_vida             fv ON fv.id_fase_vida       = b.id_fase_vida
LEFT JOIN comite_bacia_federal  cf ON cf.id_comite_federal  = b.id_comite_federal
LEFT JOIN comite_bacia_estadual ce ON ce.id_comite_estadual = b.id_comite_estadual;

COMMENT ON VIEW vw_barragem IS 'Barragem com todos os atributos resolvidos + derivados (tipo_usina, capacidade_hm3, unidade_gestao).';

-- Visão de reconstrução: as 33 colunas do CSV, na mesma ordem e com os mesmos nomes.
CREATE VIEW vw_barragem_csv AS
SELECT
    cod_snisb, cod_fiscalizador, nome, altura_fundacao_m, altura_terreno_m,
    capacidade_reservatorio, data_cadastro, tipo_material, uso_principal,
    latitude, longitude, regulada_pnsb, empreendedor, uf, municipio, fase_vida,
    orgao_fiscalizador, numero_autorizacao, data_autorizacao, regiao_hidrografica,
    cod_trecho_curso_dagua, curso_dagua, dominio_curso_dagua, comite_federal,
    comite_estadual, unidade_gestao, possui_pae, possui_plano_seguranca,
    possui_revisao_periodica, categoria_risco, dano_potencial_associado,
    barragem_autuada, completude_cadastro
FROM vw_barragem;

COMMENT ON VIEW vw_barragem_csv IS 'Reconstrói a planilha original (33 colunas) a partir do modelo normalizado.';
