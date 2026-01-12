# エンドツーエンドテストガイド

このガイドでは、Envoy Proxy Chainの完全なエンドツーエンドテストを実施する手順を説明します。

## 前提条件

- Docker & Docker Compose がインストールされていること
- OpenAI APIキー（実際のAPIテストの場合）
- curl コマンド

## テストシナリオ

このテストでは、以下のプロキシチェーンが正しく動作することを確認します：

```
Client (curl) → Envoy Proxy (8080) → llm-as-judge-proxy (8888) → OpenAI API
```

## テスト手順

### 1. 環境のセットアップ

```bash
# リポジトリのクローン
git clone <repository-url>
cd envoy-proxy-chain-to-llm-as-judge-proxy

# セットアップスクリプトの実行
bash scripts/setup.sh
```

**期待される出力:**
```
========================================
Envoy Proxy Chain Setup Script
========================================

Cloning llm-as-judge-proxy repository...
✓ Repository cloned successfully

Generating SSL certificates...
✓ Certificates generated successfully

Creating .env file...
✓ .env file created

========================================
Setup Complete!
========================================
```

**確認ポイント:**
- [ ] `llm-as-judge-proxy/` ディレクトリが作成されている
- [ ] `certs/` ディレクトリに4つのファイル（ca.crt, ca.key, server.crt, server.key）が存在する
- [ ] `.env` ファイルが作成されている

### 2. プロキシチェーンの起動

```bash
# Docker Composeでプロキシチェーンを起動
docker compose up -d

# コンテナの状態を確認
docker compose ps
```

**期待される出力:**
```
NAME                   IMAGE                         STATUS
envoy-proxy-chain      envoyproxy/envoy:v1.29-latest   Up
llm-as-judge-proxy     ...                            Up
```

**確認ポイント:**
- [ ] 両方のコンテナが "Up" 状態である
- [ ] ポート8080が公開されている
- [ ] ポート9901が公開されている（管理インターフェース）

### 3. Envoy Proxyの起動確認

```bash
# Envoyの管理インターフェースにアクセス
curl http://localhost:9901/ready
```

**期待される出力:**
```
LIVE
```

**確認ポイント:**
- [ ] ステータスコード200が返される
- [ ] レスポンスが "LIVE" である

### 4. クラスタ状態の確認

```bash
# Envoyのクラスタ状態を確認
curl http://localhost:9901/clusters
```

**期待される出力:**
```
upstream_proxy_cluster::llm-as-judge-proxy:8888::health_flags::healthy
upstream_proxy_cluster::llm-as-judge-proxy:8888::weight::1
upstream_proxy_cluster::llm-as-judge-proxy:8888::region::
...
```

**確認ポイント:**
- [ ] `upstream_proxy_cluster` が存在する
- [ ] エンドポイントが `healthy` 状態である
- [ ] `llm-as-judge-proxy:8888` が表示されている

### 5. プロキシ経由での基本的な接続テスト

```bash
# プロキシ環境変数を設定
export HTTPS_PROXY=http://localhost:8080
export HTTP_PROXY=http://localhost:8080

# HTTPSサイトへの接続テスト（OpenAI API以外）
curl -v https://www.google.com 2>&1 | grep "CONNECT"
```

**期待される出力:**
```
> CONNECT www.google.com:443 HTTP/1.1
> Host: www.google.com:443
< HTTP/1.1 200 Connection established
```

**確認ポイント:**
- [ ] CONNECTメソッドが使用されている
- [ ] ステータスコード200 Connection establishedが返される
- [ ] 接続が成功する

### 6. OpenAI APIエンドポイントへの接続テスト（認証なし）

```bash
# OpenAI APIエンドポイントへの接続テスト（401エラーが期待される）
curl -v https://api.openai.com/v1/models 2>&1 | head -30
```

**期待される出力:**
```
* Uses proxy env variable HTTPS_PROXY == 'http://localhost:8080'
*   Trying 127.0.0.1:8080...
* Connected to localhost (127.0.0.1) port 8080
* CONNECT api.openai.com:443 HTTP/1.1
* Host: api.openai.com:443
...
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
...
< HTTP/1.1 401 Unauthorized
```

**確認ポイント:**
- [ ] プロキシ（localhost:8080）への接続が成功する
- [ ] CONNECTメソッドが使用される
- [ ] "200 Connection established" が返される
- [ ] OpenAI APIから401エラーが返される（これは正常な動作）

### 7. Envoyのアクセスログ確認

```bash
# Envoyのログを確認
docker compose logs envoy-proxy | grep "upstream_proxy_chaining" | tail -5
```

**期待される出力:**
```
[2024-01-12T10:00:00.000Z] "CONNECT - HTTP/1.1" 200 - 0 1234 100 50 "-" "curl/7.88.1" "-" "api.openai.com:443" "172.20.0.2:8888" upstream_proxy_chaining
```

**確認ポイント:**
- [ ] CONNECTメソッドのログが記録されている
- [ ] ステータスコード200が記録されている
- [ ] アップストリームホスト（llm-as-judge-proxy）のIPアドレスとポートが表示されている
- [ ] `upstream_proxy_chaining` タグが含まれている

### 8. llm-as-judge-proxyのログ確認

```bash
# llm-as-judge-proxyのログを確認
docker compose logs llm-as-judge-proxy | grep -i "connect\|api.openai.com" | tail -10
```

**期待される出力:**
```
<timestamp> CONNECT api.openai.com:443
<timestamp> >> CONNECT api.openai.com:443
<timestamp> << HTTP/1.1 200 Connection established
```

**確認ポイント:**
- [ ] CONNECTリクエストが記録されている
- [ ] `api.openai.com:443` への接続が記録されている
- [ ] 200レスポンスが記録されている

### 9. OpenAI API呼び出しテスト（APIキーあり）

**注意:** 実際のAPIキーが必要です。

```bash
# APIキーを設定
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx

# モデル一覧を取得
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" | jq '.data[0].id'
```

**期待される出力:**
```
"gpt-4"
```
（または他のモデル名）

**確認ポイント:**
- [ ] ステータスコード200が返される
- [ ] JSONレスポンスが返される
- [ ] モデルのリストが取得できる

### 10. Chat Completion APIテスト

```bash
# Chat Completion APIを呼び出し
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 10
  }' | jq '.choices[0].message.content'
```

**期待される出力:**
```
"Hello! How can I assist you today?"
```
（実際のレスポンスは異なる場合があります）

**確認ポイント:**
- [ ] ステータスコード200が返される
- [ ] JSONレスポンスが返される
- [ ] `choices[0].message.content` にテキストが含まれている

### 11. プロキシチェーンの詳細確認

```bash
# 詳細なデバッグ出力付きでリクエスト
curl -v https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  2>&1 | grep -E "CONNECT|Connection established|Host:|Proxy"
```

**期待される出力:**
```
* Uses proxy env variable HTTPS_PROXY == 'http://localhost:8080'
* Proxy replied 200 to CONNECT request
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
```

**確認ポイント:**
- [ ] プロキシ環境変数が認識されている
- [ ] プロキシが200を返している
- [ ] TLSトンネルが確立されている

### 12. プロキシチェーンの完全なフロー確認

同時に複数のターミナルを開いて、以下を実行します：

**ターミナル1（Envoyログの監視）:**
```bash
docker compose logs -f envoy-proxy
```

**ターミナル2（llm-as-judge-proxyログの監視）:**
```bash
docker compose logs -f llm-as-judge-proxy
```

**ターミナル3（リクエスト実行）:**
```bash
export HTTPS_PROXY=http://localhost:8080
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

**期待される動作:**
1. ターミナル3でリクエストが実行される
2. ターミナル1（Envoy）に `CONNECT api.openai.com:443` のログが表示される
3. ターミナル2（llm-as-judge-proxy）に `CONNECT api.openai.com:443` のログが表示される
4. ターミナル3でレスポンスが返される

**確認ポイント:**
- [ ] Envoyがクライアントからの接続を受け付けている
- [ ] Envoyがllm-as-judge-proxyに転送している
- [ ] llm-as-judge-proxyがOpenAI APIに転送している
- [ ] レスポンスが正しく返ってくる

## テスト結果サマリー

全てのテストが成功した場合、以下のことが確認できます：

1. ✅ セットアップが正常に完了する
2. ✅ Docker Composeでプロキシチェーンが起動する
3. ✅ Envoy Proxyが正常に動作する
4. ✅ Envoyからllm-as-judge-proxyへの接続が確立される
5. ✅ HTTP CONNECTメソッドが正しく動作する
6. ✅ プロキシチェーン経由でHTTPS通信が可能
7. ✅ OpenAI APIへのリクエストが成功する
8. ✅ 詳細なログでプロキシチェーンを追跡できる

## トラブルシューティング

テストが失敗した場合は、[README.md](README.md)のトラブルシューティングセクションを参照してください。

## クリーンアップ

```bash
# プロキシチェーンを停止
docker compose down

# ボリュームも削除する場合
docker compose down -v
```

## 自動テストスクリプト

手動テストの代わりに、以下のスクリプトを使用できます：

```bash
# 基本的なプロキシチェーンテスト
bash scripts/test-proxy-chain.sh

# OpenAI APIテスト（APIキー必要）
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
bash scripts/test-openai-api.sh
```

## パフォーマンステスト

プロキシチェーンのパフォーマンスを測定する場合：

```bash
# レイテンシの測定
time curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" > /dev/null

# 複数回実行して平均を取る
for i in {1..10}; do
  time curl -s https://api.openai.com/v1/models \
    -H "Authorization: Bearer $OPENAI_API_KEY" > /dev/null
done
```

## セキュリティテスト

プロキシが適切に動作し、不正なリクエストを処理できることを確認：

```bash
# 不正なホストへの接続テスト（ブロックされるべき）
curl -v https://invalid-host-name.example.com

# タイムアウトテスト
curl --max-time 5 https://httpbin.org/delay/10
```

## まとめ

このテストガイドに従うことで、Envoy Proxy Chainが正しく設定され、期待通りに動作することを包括的に確認できます。
