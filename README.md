# Envoy Proxy Chain to LLM-as-Judge Proxy

Envoy Proxyを使用したForward Proxyチェーン実装です。クライアントからのHTTPSリクエストを2段階のプロキシ（Envoy → llm-as-judge-proxy）を経由してOpenAI APIに転送します。

## アーキテクチャ

```
Client → Envoy Proxy → llm-as-judge-proxy → OpenAI API
         (Port 8080)    (Internal:8888)      (api.openai.com)

         [Forward Proxy] [Forward Proxy]
```

### リクエストフロー

1. クライアントが`HTTPS_PROXY=http://localhost:8080`を設定
2. クライアントがHTTP CONNECTメソッドでEnvoyに接続
3. EnvoyがHTTP CONNECTメソッドでllm-as-judge-proxyに接続
4. llm-as-judge-proxyがOpenAI APIに接続
5. TLSトンネルが確立され、エンドツーエンドで暗号化された通信が行われる

## 特徴

- **2段階プロキシチェーン**: Envoy Proxyとllm-as-judge-proxyを連携
- **HTTP CONNECT対応**: TLSトンネリングによる透過的なHTTPS通信
- **証明書管理**: 自己署名証明書の自動生成とEnvoyでの信頼設定
- **Docker Compose**: 簡単なセットアップとデプロイ
- **詳細なログ**: プロキシチェーンの動作を確認可能

## 必要要件

- Docker & Docker Compose
- OpenSSL（証明書生成用）
- Bash（セットアップスクリプト実行用）
- curl（テスト用）

## セットアップ

### 1. リポジトリのクローン

```bash
git clone <this-repository-url>
cd envoy-proxy-chain-to-llm-as-judge-proxy
```

### 2. 初期セットアップ

セットアップスクリプトを実行して、必要な依存関係と証明書を準備します。

```bash
chmod +x scripts/*.sh
bash scripts/setup.sh
```

このスクリプトは以下を実行します：
- `llm-as-judge-proxy`リポジトリのクローン
- SSL証明書の生成（自己署名）
- `.env`ファイルの作成

### 3. 環境変数の設定（オプション）

`.env`ファイルを編集してOpenAI APIキーを設定します。

```bash
# .env
OPENAI_API_KEY=sk-xxxxxxxxxxxxx
```

**注意**: APIキーはリクエストごとに`Authorization`ヘッダーで指定することもできます。

### 4. プロキシチェーンの起動

Docker Composeでプロキシチェーンを起動します。

```bash
docker compose up -d
```

起動確認：

```bash
docker compose ps
```

以下のコンテナが起動していることを確認：
- `envoy-proxy-chain` - Envoy Proxy（ポート8080公開）
- `llm-as-judge-proxy` - LLM判定プロキシ（内部ポート8888）

### 5. ログの確認

```bash
# 全てのログを表示
docker compose logs -f

# Envoyのログのみ
docker compose logs -f envoy-proxy

# llm-as-judge-proxyのログのみ
docker compose logs -f llm-as-judge-proxy
```

## 使用方法

### 基本的な使用方法

プロキシを使用するには、環境変数でEnvoyを指定します。

```bash
export HTTPS_PROXY=http://localhost:8080
export HTTP_PROXY=http://localhost:8080
```

### テストスクリプトの実行

#### 1. プロキシチェーンのテスト

```bash
bash scripts/test-proxy-chain.sh
```

このスクリプトは以下をテストします：
- Envoy Proxyの起動状態
- HTTPS接続の動作確認
- プロキシチェーンのログ確認

#### 2. OpenAI APIのテスト

```bash
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
bash scripts/test-openai-api.sh
```

このスクリプトは以下を実行します：
- モデル一覧の取得
- Chat Completion APIの呼び出し
- プロキシチェーンの動作確認

### 手動でのテスト

#### モデル一覧の取得

```bash
export HTTPS_PROXY=http://localhost:8080
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer sk-xxxxxxxxxxxxx"
```

#### Chat Completion

```bash
export HTTPS_PROXY=http://localhost:8080
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-xxxxxxxxxxxxx" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "Hello"}
    ]
  }'
```

## エンドツーエンドテスト

### クイックテスト

簡単な動作確認を行うには、以下のコマンドを実行します：

```bash
# 1. プロキシチェーンの起動確認
make status
# または
curl http://localhost:9901/ready

# 2. プロキシ経由での接続テスト
export HTTPS_PROXY=http://localhost:8080
curl -v https://api.openai.com/v1/models 2>&1 | grep "CONNECT"
# 期待される出力: CONNECT api.openai.com:443 HTTP/1.1
```

### 完全なエンドツーエンドテスト

包括的なテスト手順については、[E2E_TEST_GUIDE.md](E2E_TEST_GUIDE.md)を参照してください。

このガイドには以下の内容が含まれています：

1. **セットアップの確認** - 全てのコンポーネントが正しくセットアップされているか
2. **起動確認** - Docker Composeでプロキシチェーンが正常に起動しているか
3. **基本的な接続テスト** - プロキシ経由でHTTPSサイトに接続できるか
4. **OpenAI APIテスト** - プロキシ経由でOpenAI APIにアクセスできるか
5. **ログの検証** - プロキシチェーンが正しく動作していることをログで確認
6. **パフォーマンステスト** - レイテンシの測定

### テスト結果の例

正常に動作している場合の期待される出力：

#### 1. プロキシチェーンの接続テスト

```bash
$ curl -v https://api.openai.com/v1/models
* Uses proxy env variable HTTPS_PROXY == 'http://localhost:8080'
*   Trying 127.0.0.1:8080...
* Connected to localhost (127.0.0.1) port 8080
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
<
* CONNECT phase completed
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
...
```

**確認ポイント:**
- ✅ プロキシ（localhost:8080）への接続が成功
- ✅ CONNECTメソッドが使用されている
- ✅ "200 Connection established" が返される

#### 2. Envoyのアクセスログ

```bash
$ docker compose logs envoy-proxy | grep "upstream_proxy_chaining"
[2024-01-12T10:15:23.456Z] "CONNECT - HTTP/1.1" 200 - 0 2048 150 45 "-" "curl/7.88.1" "uuid" "api.openai.com:443" "172.20.0.2:8888" upstream_proxy_chaining
```

**確認ポイント:**
- ✅ CONNECTメソッドのログが記録されている
- ✅ ステータスコード200
- ✅ アップストリーム先が llm-as-judge-proxy（172.20.0.2:8888）
- ✅ `upstream_proxy_chaining` タグが含まれている

#### 3. llm-as-judge-proxyのログ

```bash
$ docker compose logs llm-as-judge-proxy | grep "CONNECT"
[2024-01-12 10:15:23] 172.20.0.3:54321: CONNECT api.openai.com:443
[2024-01-12 10:15:23] >> CONNECT api.openai.com:443
[2024-01-12 10:15:23] << HTTP/1.1 200 Connection established
```

**確認ポイント:**
- ✅ Envoyからのリクエストを受信
- ✅ OpenAI APIへCONNECTリクエストを転送
- ✅ 接続確立に成功

#### 4. プロキシチェーンのフロー確認

```
┌─────────┐         ┌──────────────┐         ┌────────────────────┐         ┌─────────────┐
│  curl   │─(1)────>│ Envoy Proxy  │─(2)────>│ llm-as-judge-proxy │─(3)────>│ OpenAI API  │
│         │<─(4)────│   :8080      │<─(5)────│      :8888         │<─(6)────│  :443       │
└─────────┘         └──────────────┘         └────────────────────┘         └─────────────┘

(1) CONNECT api.openai.com:443 HTTP/1.1
(2) CONNECT api.openai.com:443 HTTP/1.1
(3) TCP connection to api.openai.com:443
(4) HTTP/1.1 200 Connection established
(5) HTTP/1.1 200 Connection established
(6) HTTP/1.1 200 Connection established

その後、TLSトンネル経由でエンドツーエンドの暗号化通信
```

### 自動テストスクリプト

プロジェクトには2つのテストスクリプトが含まれています：

```bash
# 基本的なプロキシチェーンのテスト
bash scripts/test-proxy-chain.sh

# OpenAI APIを使った実際のテスト（APIキー必要）
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
bash scripts/test-openai-api.sh
```

または、Makefileを使用：

```bash
make test        # 基本テスト
make test-api    # OpenAI APIテスト（OPENAI_API_KEY必要）
```

## プロキシチェーンの動作確認

正常に動作している場合、Envoyのログに以下のような出力が表示されます：

```
[2024-01-12T10:00:00.000Z] "CONNECT - HTTP/1.1" 200 - 0 1234 100 50 "-" "-" "-" "api.openai.com:443" "llm-as-judge-proxy:8888" upstream_proxy_chaining
```

ログの読み方：
- **CONNECT**: HTTP CONNECTメソッドが使用された
- **200**: 接続が成功した
- **api.openai.com:443**: 最終的な接続先
- **llm-as-judge-proxy:8888**: 次段のプロキシ
- **upstream_proxy_chaining**: プロキシチェーンのマーカー

## 設定ファイル

### envoy.yaml

Envoy Proxyの設定ファイルです。主な設定：

- **Listener**: ポート8080でHTTP/HTTPS接続を受け付け
- **HTTP Connection Manager**: HTTP CONNECTメソッドをサポート
- **Cluster**: `llm-as-judge-proxy:8888`へのアップストリーム接続
- **TLS設定**: 自己署名証明書の信頼（`/etc/envoy/certs/ca.crt`）

### docker-compose.yaml

Docker Compose設定ファイルです。以下のサービスを定義：

1. **envoy-proxy**: Envoy Proxyコンテナ
   - ポート8080を公開（Forward Proxy）
   - ポート9901を公開（管理インターフェース）

2. **llm-as-judge-proxy**: LLM判定プロキシコンテナ
   - 内部ポート8888で動作
   - Envoyから接続を受け付ける

## トラブルシューティング

### 証明書エラー

**症状**: Envoyが起動時に証明書エラーを出す

```bash
# 証明書を再生成
rm -rf certs
bash scripts/generate-certs.sh
docker compose restart
```

### llm-as-judge-proxyに接続できない

**症状**: Envoyのログに`upstream connect error`が表示される

**確認事項**:
1. llm-as-judge-proxyコンテナが起動しているか確認
   ```bash
   docker compose ps llm-as-judge-proxy
   ```

2. ネットワーク接続を確認
   ```bash
   docker compose exec envoy-proxy ping llm-as-judge-proxy
   ```

3. llm-as-judge-proxyのログを確認
   ```bash
   docker compose logs llm-as-judge-proxy
   ```

### プロキシが動作しない

**症状**: curlが`Proxy CONNECT aborted`エラーを返す

**確認事項**:
1. Envoy Proxyが起動しているか確認
   ```bash
   curl http://localhost:9901/ready
   ```

2. プロキシ環境変数が正しく設定されているか確認
   ```bash
   echo $HTTPS_PROXY
   echo $HTTP_PROXY
   ```

3. Envoyの設定が正しいか確認
   ```bash
   docker compose logs envoy-proxy | grep error
   ```

### DNS解決の問題

**症状**: `no healthy upstream`エラー

**解決方法**:
```bash
# DNSキャッシュをクリアして再起動
docker compose down
docker compose up -d
```

### ログレベルの変更

デバッグ情報を増やす場合：

```yaml
# docker-compose.yaml
services:
  envoy-proxy:
    command: ["-c", "/etc/envoy/envoy.yaml", "-l", "trace"]
```

## 管理インターフェース

Envoy Proxyの管理インターフェースは`http://localhost:9901`でアクセスできます。

主な機能：
- `/stats`: 統計情報
- `/clusters`: クラスタ情報
- `/config_dump`: 現在の設定
- `/ready`: ヘルスチェック

例：
```bash
# 統計情報の確認
curl http://localhost:9901/stats

# クラスタ状態の確認
curl http://localhost:9901/clusters
```

## 開発・カスタマイズ

### Envoy設定のカスタマイズ

`envoy.yaml`を編集して、必要に応じて設定を変更できます。

主なカスタマイズポイント：
- リスニングポート（現在8080）
- ログフォーマット
- タイムアウト設定
- TLS設定

設定変更後は再起動が必要：
```bash
docker compose restart envoy-proxy
```

### llm-as-judge-proxyの設定

`llm-as-judge-proxy`の設定は、そのリポジトリのドキュメントを参照してください。

## セキュリティについて

### 開発環境での使用

この実装は**開発・テスト環境**での使用を想定しています。

セキュリティ上の注意点：
- 自己署名証明書を使用（本番環境では正規のCA発行証明書を使用）
- TLS検証が簡略化されている
- ログに詳細情報が出力される

### 本番環境での使用

本番環境で使用する場合は、以下の対策が必要です：

1. **正規の証明書を使用**
   - Let's Encryptなどから取得
   - 自己署名証明書は使用しない

2. **認証・認可の実装**
   - プロキシへのアクセス制御
   - APIキーの適切な管理

3. **ログの管理**
   - センシティブ情報のマスキング
   - ログレベルの調整

4. **ネットワークセキュリティ**
   - ファイアウォール設定
   - 不要なポートの閉鎖

## ライセンス

このプロジェクトのライセンスについては、LICENSEファイルを参照してください。

## 参考リンク

- [Envoy Proxy公式ドキュメント](https://www.envoyproxy.io/docs)
- [llm-as-judge-proxy](https://github.com/nyasukun/llm-as-judge-proxy)
- [OpenAI API Documentation](https://platform.openai.com/docs)

## サポート

問題が発生した場合は、Issueを作成してください。
