# tampa-virtual

Para MacBook com o sensor da tampa quebrado (lid angle sensor): fechar a tampa não faz nada.

Usa o trackpad para imitar a tampa: fechada, a tela deitada sobre ele aparece como um único contato gigante (~67 x 42 mm) no centro. Mão espalmada dá vários contatos menores e não dispara. Funciona com luz ou no escuro.

- fechou, com monitor externo e na tomada: apaga a tela interna e segue nos monitores
- fechou, sem monitor ou na bateria: repouso
- abriu: religa a tela interna

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/wanderfran/tampa-virtual/main/instalar.sh | bash
```

## Remover

```bash
curl -fsSL https://raw.githubusercontent.com/wanderfran/tampa-virtual/main/desinstalar.sh | bash
```

## Recompilar

```bash
swiftc -O tampa.swift -o tampa-virtual
```

Limitação: com o Mac em repouso, abrir a tampa não acorda; aperte uma tecla ou o Touch ID.

Registro em `~/Library/Logs/tampa-virtual.log`. Testado em MacBook Pro 14" M1 Pro (MacBookPro18,3), macOS 26.5.
