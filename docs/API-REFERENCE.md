# API Reference

Documentacao de referencia para consumo das APIs da ACDG Brasil.

## Base URLs

| Ambiente | URL |
|----------|-----|
| Producao | `https://social-care.acdgbrasil.com.br` |
| Homologacao | `https://social-care-hml.acdgbrasil.com.br` |
| Identity Provider | `https://auth.acdgbrasil.com.br` |

## Autenticacao

Todos os endpoints protegidos exigem:

- **Header:** `Authorization: Bearer <JWT_TOKEN>`
- **JWT** validado contra JWKS: `https://auth.acdgbrasil.com.br/oauth/v2/keys`
- **Issuer:** `https://auth.acdgbrasil.com.br`
- **Token Endpoint:** `https://auth.acdgbrasil.com.br/oauth/v2/token`
- **Roles** extraidas do claim `urn:zitadel:iam:org:project:roles`

Para operacoes de escrita (POST/PUT/DELETE), o header **`X-Actor-Id`** e obrigatorio (auditoria).

### Roles

| Role | Permissao |
|------|-----------|
| `social_worker` | Leitura e escrita completa |
| `owner` | Somente leitura |
| `admin` | Acesso completo |

## Formato de Resposta

Todas as respostas (exceto 204 e Health) seguem o envelope `StandardResponse<T>`:

```json
{
  "data": { },
  "meta": {
    "timestamp": "2026-03-12T10:30:00Z"
  }
}
```

### Codigos de Erro

| Status | Significado |
|--------|-------------|
| `400` | Request invalido |
| `401` | JWT ausente ou invalido |
| `403` | Role insuficiente |
| `404` | Recurso nao encontrado |
| `500` | Erro interno |
| `503` | Banco indisponivel |

---

## Health (publico)

| Metodo | Path | Descricao |
|--------|------|-----------|
| `GET` | `/health` | Liveness probe |
| `GET` | `/ready` | Readiness probe (verifica banco) |

---

## Registry — Pacientes

**Base:** `/api/v1/patients`

### Escrita (role: `social_worker`)

| Metodo | Path | Descricao |
|--------|------|-----------|
| `POST` | `/api/v1/patients` | Registrar paciente |
| `POST` | `/api/v1/patients/{patientId}/family-members` | Adicionar membro familiar |
| `DELETE` | `/api/v1/patients/{patientId}/family-members/{memberId}` | Remover membro familiar |
| `PUT` | `/api/v1/patients/{patientId}/primary-caregiver` | Atribuir cuidador principal |
| `PUT` | `/api/v1/patients/{patientId}/social-identity` | Atualizar identidade social |

### Leitura (role: `social_worker`, `owner`, `admin`)

| Metodo | Path | Descricao |
|--------|------|-----------|
| `GET` | `/api/v1/patients/{patientId}` | Buscar paciente por ID |
| `GET` | `/api/v1/patients/by-person/{personId}` | Buscar por Person ID |
| `GET` | `/api/v1/patients/{patientId}/audit-trail` | Trilha de auditoria |

> Query param opcional para audit-trail: `?eventType=<tipo>`

### POST `/api/v1/patients`

```json
{
  "personId": "string",
  "initialDiagnoses": [
    { "icdCode": "string", "date": "2026-01-15", "description": "string" }
  ],
  "personalData": {
    "firstName": "string",
    "lastName": "string",
    "motherName": "string",
    "nationality": "string",
    "sex": "string",
    "socialName": "string | null",
    "birthDate": "2000-01-01",
    "phone": "string | null"
  },
  "civilDocuments": {
    "cpf": "string | null",
    "nis": "string | null",
    "rgDocument": {
      "number": "string",
      "issuingState": "string",
      "issuingAgency": "string",
      "issueDate": "2020-01-01"
    }
  },
  "address": {
    "cep": "string | null",
    "isShelter": false,
    "residenceLocation": "string",
    "street": "string | null",
    "neighborhood": "string | null",
    "number": "string | null",
    "complement": "string | null",
    "state": "string",
    "city": "string"
  },
  "socialIdentity": {
    "typeId": "string",
    "description": "string | null"
  },
  "prRelationshipId": "string"
}
```

### POST `.../family-members`

```json
{
  "memberId": "string",
  "relationshipId": "string",
  "name": "string",
  "birthDate": "2000-01-01",
  "sex": "string"
}
```

### PUT `.../primary-caregiver`

```json
{ "memberId": "string" }
```

### PUT `.../social-identity`

```json
{ "typeId": "string", "description": "string | null" }
```

---

## Assessment — Avaliacoes

**Base:** `/api/v1/patients/{patientId}`
**Role:** `social_worker` | **Header:** `X-Actor-Id`

| Metodo | Path | Descricao |
|--------|------|-----------|
| `PUT` | `.../housing-condition` | Condicao habitacional |
| `PUT` | `.../socioeconomic-situation` | Situacao socioeconomica |
| `PUT` | `.../work-and-income` | Trabalho e renda |
| `PUT` | `.../educational-status` | Situacao educacional |
| `PUT` | `.../health-status` | Condicao de saude |
| `PUT` | `.../community-support-network` | Rede de apoio comunitaria |
| `PUT` | `.../social-health-summary` | Resumo socio-sanitario |

Todos retornam **204 No Content** em caso de sucesso.

### PUT `.../housing-condition`

```json
{
  "type": "string",
  "wallMaterial": "string",
  "numberOfRooms": 3,
  "numberOfBedrooms": 2,
  "numberOfBathrooms": 1,
  "waterSupply": "string",
  "hasPipedWater": true,
  "electricityAccess": "string",
  "sewageDisposal": "string",
  "wasteCollection": "string",
  "accessibilityLevel": "string",
  "isInGeographicRiskArea": false,
  "hasDifficultAccess": false,
  "isInSocialConflictArea": false,
  "hasDiagnosticObservations": false
}
```

### PUT `.../socioeconomic-situation`

```json
{
  "totalFamilyIncome": 2500.00,
  "incomePerCapita": 625.00,
  "receivesSocialBenefit": true,
  "socialBenefits": [
    {
      "benefitName": "BPC",
      "amount": 1412.00,
      "beneficiaryId": "string",
      "benefitTypeId": "string | null",
      "birthCertificateNumber": "string | null",
      "deceasedCpf": "string | null"
    }
  ],
  "mainSourceOfIncome": "string",
  "hasUnemployed": false
}
```

### PUT `.../work-and-income`

```json
{
  "individualIncomes": [
    {
      "memberId": "string",
      "occupationId": "string",
      "hasWorkCard": true,
      "monthlyAmount": 1800.00
    }
  ],
  "socialBenefits": [
    {
      "benefitName": "string",
      "amount": 1412.00,
      "beneficiaryId": "string",
      "benefitTypeId": "string | null",
      "birthCertificateNumber": "string | null",
      "deceasedCpf": "string | null"
    }
  ],
  "hasRetiredMembers": false
}
```

### PUT `.../educational-status`

```json
{
  "memberProfiles": [
    {
      "memberId": "string",
      "canReadWrite": true,
      "attendsSchool": true,
      "educationLevelId": "string"
    }
  ],
  "programOccurrences": [
    {
      "memberId": "string",
      "date": "2026-01-15",
      "effectId": "string",
      "isSuspensionRequested": false
    }
  ]
}
```

### PUT `.../health-status`

```json
{
  "deficiencies": [
    {
      "memberId": "string",
      "deficiencyTypeId": "string",
      "needsConstantCare": true,
      "responsibleCaregiverName": "string | null"
    }
  ],
  "gestatingMembers": [
    {
      "memberId": "string",
      "monthsGestation": 6,
      "startedPrenatalCare": true
    }
  ],
  "constantCareNeeds": ["string"],
  "foodInsecurity": false
}
```

### PUT `.../community-support-network`

```json
{
  "hasRelativeSupport": true,
  "hasNeighborSupport": false,
  "familyConflicts": "string",
  "patientParticipatesInGroups": false,
  "familyParticipatesInGroups": false,
  "patientHasAccessToLeisure": true,
  "facesDiscrimination": false
}
```

### PUT `.../social-health-summary`

```json
{
  "requiresConstantCare": true,
  "hasMobilityImpairment": false,
  "functionalDependencies": ["string"],
  "hasRelevantDrugTherapy": true
}
```

---

## Care — Cuidado

**Base:** `/api/v1/patients/{patientId}`
**Role:** `social_worker` | **Header:** `X-Actor-Id`

| Metodo | Path | Descricao | Resposta |
|--------|------|-----------|----------|
| `POST` | `.../appointments` | Registrar atendimento | `StandardResponse<IdResponse>` |
| `PUT` | `.../intake-info` | Info de acolhimento | 204 No Content |

### POST `.../appointments`

```json
{
  "professionalId": "string",
  "summary": "string | null",
  "actionPlan": "string | null",
  "type": "string | null",
  "date": "2026-03-12 | null"
}
```

### PUT `.../intake-info`

```json
{
  "ingressTypeId": "string",
  "originName": "string | null",
  "originContact": "string | null",
  "serviceReason": "string",
  "linkedSocialPrograms": [
    { "programId": "string", "observation": "string | null" }
  ]
}
```

---

## Protection — Protecao

**Base:** `/api/v1/patients/{patientId}`
**Role:** `social_worker` | **Header:** `X-Actor-Id`

| Metodo | Path | Descricao | Resposta |
|--------|------|-----------|----------|
| `PUT` | `.../placement-history` | Historico de acolhimento | 204 No Content |
| `POST` | `.../violation-reports` | Reportar violacao de direitos | `StandardResponse<IdResponse>` |
| `POST` | `.../referrals` | Criar encaminhamento | `StandardResponse<IdResponse>` |

### PUT `.../placement-history`

```json
{
  "registries": [
    {
      "memberId": "string",
      "startDate": "2025-01-01",
      "endDate": "2025-06-01 | null",
      "reason": "string"
    }
  ],
  "collectiveSituations": {
    "homeLossReport": "string | null",
    "thirdPartyGuardReport": "string | null"
  },
  "separationChecklist": {
    "adultInPrison": false,
    "adolescentInInternment": false
  }
}
```

### POST `.../violation-reports`

```json
{
  "victimId": "string",
  "violationType": "string",
  "violationTypeId": "string | null",
  "reportDate": "2026-03-12 | null",
  "incidentDate": "2026-03-01 | null",
  "descriptionOfFact": "string",
  "actionsTaken": "string | null"
}
```

### POST `.../referrals`

```json
{
  "referredPersonId": "string",
  "professionalId": "string | null",
  "destinationService": "string",
  "reason": "string",
  "date": "2026-03-12 | null"
}
```

---

## Lookup — Tabelas de Dominio

**Base:** `/api/v1/dominios`
**Role:** `social_worker`, `owner`, `admin`

| Metodo | Path | Descricao |
|--------|------|-----------|
| `GET` | `/api/v1/dominios/{tableName}` | Buscar itens de uma tabela |

### Tabelas disponiveis

| `tableName` | Descricao |
|-------------|-----------|
| `dominio_tipo_identidade` | Tipos de identidade social |
| `dominio_parentesco` | Graus de parentesco |
| `dominio_condicao_ocupacao` | Condicoes de ocupacao |
| `dominio_escolaridade` | Niveis de escolaridade |
| `dominio_efeito_condicionalidade` | Efeitos de condicionalidade |
| `dominio_tipo_deficiencia` | Tipos de deficiencia |
| `dominio_programa_social` | Programas sociais |
| `dominio_tipo_ingresso` | Tipos de ingresso |
| `dominio_tipo_beneficio` | Tipos de beneficio |
| `dominio_tipo_violacao` | Tipos de violacao |
| `dominio_servico_vinculo` | Tipos de vinculo de servico |
| `dominio_tipo_medida` | Tipos de medida |
| `dominio_unidade_realizacao` | Unidades de realizacao |

### Resposta

```json
{
  "data": [
    { "id": "uuid", "codigo": "001", "descricao": "Descricao do item" }
  ],
  "meta": { "timestamp": "2026-03-12T00:00:00Z" }
}
```

---

## Resumo

| Grupo | Endpoints |
|-------|-----------|
| Health | 2 |
| Registry | 8 |
| Assessment | 7 |
| Care | 2 |
| Protection | 3 |
| Lookup | 1 (13 tabelas) |
| **Total** | **24** |
