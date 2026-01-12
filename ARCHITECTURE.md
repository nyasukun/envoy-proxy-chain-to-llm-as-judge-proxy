# アーキテクチャドキュメント

## システム概要

このプロジェクトは、Envoy Proxyとllm-as-judge-proxyを使用した2段階のForward Proxyチェーンを実装しています。

## コンポーネント構成

```
┌─────────┐         ┌──────────────┐         ┌────────────────────┐         ┌─────────────┐
│ Client  │────────>│ Envoy Proxy  │────────>│ llm-as-judge-proxy │────────>│ OpenAI API  │
│         │ :8080   │ (1st Proxy)  │ :8888   │   (2nd Proxy)      │ :443    │             │
└─────────┘         └──────────────┘         └────────────────────┘         └─────────────┘
                            │
                            │ :9901
                            ▼
                    ┌──────────────┐
                    │ Admin UI     │
                    └──────────────┘
```

## データフロー

### 1. HTTPS通信の場合（HTTP CONNECT）

```
1. Client → Envoy
   CONNECT api.openai.com:443 HTTP/1.1
   Host: api.openai.com:443

2. Envoy → llm-as-judge-proxy
   CONNECT api.openai.com:443 HTTP/1.1
   Host: api.openai.com:443

3. llm-as-judge-proxy → OpenAI API
   TCP connection to api.openai.com:443

4. HTTP 200 Connection Established ← llm-as-judge-proxy
   ← Envoy

5. Client ⟷ OpenAI API
   TLS tunnel established
   Encrypted communication
```

### 2. HTTP通信の場合

```
1. Client → Envoy
   GET http://example.com/ HTTP/1.1
   Host: example.com

2. Envoy → llm-as-judge-proxy
   GET http://example.com/ HTTP/1.1
   Host: example.com

3. llm-as-judge-proxy → example.com
   GET / HTTP/1.1
   Host: example.com

4. Response ← example.com
   ← llm-as-judge-proxy
   ← Envoy
   ← Client
```

## Envoy Proxy設定詳細

### リスナー設定

```yaml
listeners:
- name: forward_proxy_listener
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 8080
```

- **ポート8080**: HTTP/HTTPSプロキシとして動作
- **0.0.0.0**: すべてのネットワークインターフェースでリスン

### HTTP Connection Manager

```yaml
http_connection_manager:
  stat_prefix: ingress_http
  upgrade_configs:
  - upgrade_type: CONNECT
```

- **upgrade_type: CONNECT**: HTTP CONNECTメソッドをサポート
- **stat_prefix**: メトリクスのプレフィックス

### ルーティング設定

```yaml
routes:
- match:
    connect_matcher: {}
  route:
    cluster: upstream_proxy_cluster
    upgrade_configs:
    - upgrade_type: CONNECT
      connect_config: {}
```

- **connect_matcher**: CONNECTリクエストにマッチ
- **upstream_proxy_cluster**: llm-as-judge-proxyへルーティング

### クラスタ設定

```yaml
clusters:
- name: upstream_proxy_cluster
  type: STRICT_DNS
  load_assignment:
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: llm-as-judge-proxy
              port_value: 8888
```

- **STRICT_DNS**: DNS名前解決を使用
- **llm-as-judge-proxy:8888**: 次段のプロキシ

### TLS設定

```yaml
transport_socket:
  name: envoy.transport_sockets.tls
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
    common_tls_context:
      validation_context:
        trust_chain_filename: /etc/envoy/certs/ca.crt
```

- **trust_chain_filename**: 信頼するCA証明書
- llm-as-judge-proxyの自己署名証明書を検証

## llm-as-judge-proxy

llm-as-judge-proxyは2つの役割を持ちます：

1. **Forward Proxy**: OpenAI APIへのリクエストを転送
2. **LLM Judge**: リクエスト/レスポンスの検証（オプション）

### 通信プロトコル

- **待ち受け**: HTTPS（ポート8888）
- **証明書**: 自己署名証明書（開発環境）
- **プロトコル**: HTTP/1.1 with CONNECT support

## 証明書管理

### 証明書の構成

```
certs/
├── ca.crt        # CA証明書（Envoyが信頼）
├── ca.key        # CA秘密鍵
├── server.crt    # サーバ証明書（llm-as-judge-proxyが使用）
└── server.key    # サーバ秘密鍵（llm-as-judge-proxyが使用）
```

### 証明書の用途

1. **ca.crt**: Envoyがllm-as-judge-proxyの証明書を検証するために使用
2. **server.crt/server.key**: llm-as-judge-proxyがTLS接続を受け付けるために使用

### SAN（Subject Alternative Name）

サーバ証明書には以下のSANが含まれています：

- DNS: llm-as-judge-proxy
- DNS: localhost
- IP: 127.0.0.1

## Docker Networking

### ネットワーク構成

```yaml
networks:
  proxy-chain-network:
    driver: bridge
```

- **bridge**: Docker bridgeネットワーク
- コンテナ間で名前解決が可能
- `llm-as-judge-proxy`という名前でDNS解決される

### ポートマッピング

- **8080:8080**: Envoy Proxy（ホストからアクセス可能）
- **9901:9901**: Envoy Admin UI（ホストからアクセス可能）
- **8888**: llm-as-judge-proxy（コンテナ間のみ）

## ログとモニタリング

### アクセスログフォーマット

```
[START_TIME] "METHOD PATH PROTOCOL" RESPONSE_CODE FLAGS RX_BYTES TX_BYTES DURATION
UPSTREAM_TIME "X-FORWARDED-FOR" "USER-AGENT" "REQUEST-ID" "AUTHORITY" "UPSTREAM_HOST" TAG
```

### 重要なログフィールド

- **METHOD**: CONNECT、GET、POSTなど
- **RESPONSE_CODE**: HTTPステータスコード
- **UPSTREAM_HOST**: 次段のプロキシ（llm-as-judge-proxy:8888）
- **TAG**: `upstream_proxy_chaining`でプロキシチェーンを識別

### 管理インターフェース

Envoyの管理インターフェース（:9901）で以下の情報を取得可能：

- `/stats`: メトリクス
- `/clusters`: クラスタ状態
- `/config_dump`: 現在の設定
- `/ready`: ヘルスチェック

## セキュリティ考慮事項

### 開発環境

- 自己署名証明書を使用
- TLS検証を簡略化
- 詳細なログ出力

### 本番環境への移行

以下の変更が必要：

1. **証明書**
   - 正規のCA発行証明書を使用
   - 証明書の定期的な更新

2. **認証・認可**
   - プロキシへのアクセス制御
   - API認証の実装

3. **ログ**
   - センシティブ情報のマスキング
   - ログレベルの調整（info/warn）

4. **ネットワーク**
   - ファイアウォール設定
   - 必要最小限のポート公開

## パフォーマンス

### 設定パラメータ

```yaml
connect_timeout: 30s
```

- **connect_timeout**: アップストリーム接続のタイムアウト
- 必要に応じて調整可能

### スケーリング

- Envoyは複数のワーカースレッドを使用
- Docker Composeの`replicas`でスケールアウト可能
- ロードバランサーを前段に配置可能

## トラブルシューティングフロー

```
[接続失敗]
    │
    ├─ Envoy起動確認 → curl http://localhost:9901/ready
    │
    ├─ llm-as-judge-proxy起動確認 → docker compose ps
    │
    ├─ 証明書確認 → ls -la certs/
    │
    ├─ ネットワーク確認 → docker compose exec envoy-proxy ping llm-as-judge-proxy
    │
    └─ ログ確認 → docker compose logs
```

## 拡張性

### カスタマイズポイント

1. **フィルタの追加**
   - レート制限
   - 認証
   - ロギング

2. **メトリクスの追加**
   - Prometheus連携
   - カスタムメトリクス

3. **複数バックエンド**
   - 複数のLLMプロバイダー対応
   - 負荷分散

## 参考資料

- [Envoy Proxy - HTTP Connection Manager](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/http_conn_man)
- [Envoy Proxy - CONNECT Support](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/upgrades)
- [HTTP CONNECT Method - RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#name-connect)
