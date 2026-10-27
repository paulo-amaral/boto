# Boto: segurança e normas (NIST, FIPS 140-3, DISA)

Estado em 2026-10-26. Este documento separa o que foi verificado em fonte oficial do que é inferência. Não é parecer jurídico nem declaração de conformidade.

## Conclusão

O Boto não está certificado nem autorizado em nenhuma dessas normas, e não deve ser descrito assim. Ele é um app local de uso pessoal, que só usa a rede para ler itens do GitHub quando você pede, e que não implementa criptografia própria. A proteção dos dados em repouso depende do macOS (FileVault). O que o app faz é verificar isso, avisar quando falta e manter o binário endurecido.

## O que cada norma é

| Norma | Aplica-se a | Aplica-se ao Boto? |
|---|---|---|
| FIPS 140-3 | Módulos criptográficos validados pelo CMVP do NIST | Não ao app. O app só pode usar módulos validados do sistema. |
| NIST SP 800-53 | Catálogo de controles para sistemas de informação | Como referência de controles. Não há autorização formal para um app pessoal. |
| NIST SP 800-171 | Proteção de CUI em sistemas não federais | Só se o Boto tratar CUI de contrato federal dos EUA. |
| DISA Cloud SRG, IL2 a IL6 | Autorização de serviços de nuvem para dados do DoD | Não. É processo de autorização de provedores de nuvem. |

## Verificado em fonte

- **Módulos da Apple.** A página [Apple: certificações do macOS](https://support.apple.com/guide/certifications/apc35eb3dc4fa/web) lista módulos corecrypto FIPS 140-3. Pela leitura dela em 2026-10-26:
  - macOS 14 (Apple silicon): módulo v14.0, usuário (certificado 5263) e kernel (5304), validados.
  - macOS 15 (Apple silicon): módulo v18.3, usuário (5184) e kernel (5387), validados.
  - macOS 26: usuário e kernel em "Review"; Secure Key Store em "Implementation Under Test". Sem certificado.
  - **Não vi linha para o macOS 27**, que é o sistema desta máquina.
  - A Apple informa que a validação só ocorre contra uma versão final lançada do macOS.
- **Discrepância a conferir.** Uma busca anterior associou o certificado 4951 a módulo Intel de usuário e o 4956 a Intel kernel; a página da Apple, lida depois, associa 4956 ao módulo Intel de usuário. Confirme cada número na [busca do CMVP](https://csrc.nist.gov/projects/cryptographic-module-validation-program) antes de citar.
- **NIST SP 800-53.** A página [SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) mostra "Rev. 5 (Final)" de setembro de 2020 e registra uma versão 5.2.0 de 27 de agosto de 2025, com controles novos e revisados.

## Não verificado em fonte oficial

- **SP 800-171.** Fontes secundárias dizem que a Rev. 3 foi publicada em 14 de maio de 2024 e a Rev. 2 foi retirada no mesmo dia, e que o DoD manteve a Rev. 2 para DFARS e CMMC por desvio de classe. Não confirmei isso em página do NIST nem do DoD. As fontes divergem em datas.
- **Níveis IL.** As definições vieram de textos de fornecedores, não do próprio SRG da DISA. Resumo não verificado: IL2 dados públicos ou não críticos, IL4 CUI, IL5 CUI de maior sensibilidade e sistemas de segurança nacional, IL6 classificado até SECRET.
- **Se o app, rodando no macOS 27, usa um módulo validado.** Não encontrei fonte que diga isso. Não afirmo.

## O que o Boto faz hoje

| Medida | Estado | Observação |
|---|---|---|
| Aviso quando o FileVault está desligado | Feito | `fdesetup status`; só mostra faixa quando a resposta é "Off". Resposta ilegível conta como desconhecido, sem alarme. |
| Criptografia própria | Não faz | Decisão: não criar criptografia sem módulo validado. |
| Rede | Só GitHub, por ação do usuário | HTTPS para `api.github.com` ao vincular ou atualizar uma issue ou PR. Somente leitura. Sem telemetria. O sistema não impede outras conexões, porque não há sandbox. |
| Token do GitHub | Keychain | Token fine-grained com leitura em Issues e Pull requests. Nunca vai para o banco nem para logs. Sem token, só itens públicos. A criptografia de transporte é a do `URLSession` do sistema; não verifiquei qual módulo criptográfico ela usa. |
| Hardened runtime | Feito | Assinatura com `--options runtime` (ad hoc; sem Developer ID). |
| Sandbox | Desligado | Troca consciente para permitir referências a pastas e arquivos locais. Reduz o isolamento do processo. |
| Registro de auditoria | Pendente | O histórico de atividade planejado cobre parte disso. |
| Banco local | Sem proteção própria | Fica em `Application Support/Boto/Boto.store`, numa pasta só do usuário (0700), protegido pelo FileVault. Antes usava o `default.store` do SwiftData, compartilhado com outros apps sem sandbox; isso foi abandonado depois de uma perda de dados. Uma cópia diária (as 7 últimas) fica em `Backups/`, com pasta 0700 e arquivos 0600; tem o mesmo conteúdo do banco e a mesma sensibilidade. |

## Se o objetivo for aderência formal

Seria outro projeto: definir o escopo (que dados, que contrato), escolher a revisão do 800-171 exigida pelo contrato, mapear controle a controle com os textos oficiais, decidir sandbox e criptografia do banco e, se for exigido FIPS, usar apenas módulos com certificado válido para a versão exata do macOS em uso.

## Fontes

- [Apple: certificações de segurança do macOS](https://support.apple.com/guide/certifications/apc35eb3dc4fa/web)
- [NIST CMVP, certificado 4951](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4951)
- [NIST CMVP, certificado 4956](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4956)
- [NIST SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [NIST SP 800-171 Rev. 3 (versão pública preliminar, não a final)](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-171r3.fpd.pdf)
- [Understanding DoD cloud computing impact levels, Second Front](https://www.secondfront.com/insights/understanding-dod-cloud-computing-impact-levels) (fornecedor, não oficial)
