.PHONY: vm-create vm-start vm-stop vm-destroy vm-shell vm-gui test logs audit-denied audit-summary monitor session serve

# ==========================================
# VM ライフサイクル管理
# ==========================================

# VM の作成・プロビジョニング（初回のみ）
vm-create:
	multipass launch --name goose-box --cloud-init vm/cloud-init.yaml --cpus 2 --memory 4G --disk 20G
	@echo ""
	@echo "=== VM 作成完了 ==="
	@echo "cloud-init のプロビジョニングが完了するまで数分かかります。"
	@echo "進捗確認: multipass exec goose-box -- tail -f /var/log/cloud-init-output.log"

# VM の起動
vm-start:
	multipass start goose-box

# VM の停止
vm-stop:
	multipass stop goose-box

# VM の完全破棄（クリーンな初期状態に復元）
vm-destroy:
	multipass delete goose-box && multipass purge

# VM へのシェルアクセス
vm-shell:
	multipass shell goose-box

# ==========================================
# GUI デスクトップ接続
# ==========================================

# GUI 接続情報の表示
vm-gui:
	@echo "=== GUI デスクトップ接続情報 ==="
	@echo "VM IP: $$(multipass info goose-box | grep IPv4 | awk '{print $$2}')"
	@echo ""
	@echo "RDP 接続: rdesktop $$(multipass info goose-box | grep IPv4 | awk '{print $$2}')"
	@echo "  または: xfreerdp /v:$$(multipass info goose-box | grep IPv4 | awk '{print $$2}')"

# ==========================================
# Goose セッション管理
# ==========================================

# ワークスペースをVMに転送して Goose CLI セッションを開始
session:
	multipass transfer workspace/ goose-box:/home/goose/workspace/ 2>/dev/null || true
	multipass exec goose-box -- sudo -u goose /opt/goose-box/bin/start-goose.sh

# Goose ACP サーバーを起動（Goose Desktop 連携用）
serve:
	multipass transfer workspace/ goose-box:/home/goose/workspace/ 2>/dev/null || true
	multipass exec goose-box -- sudo -u goose goose serve --host 0.0.0.0 --port 3284

# ==========================================
# 通信遮断テスト
# ==========================================

# 通信遮断テストの実行
test:
	multipass exec goose-box -- /opt/goose-box/bin/test-egress.sh

# ==========================================
# 監査ログ・ダッシュボード
# ==========================================

# プロキシの JSON 監査ログをリアルタイム表示
logs:
	multipass exec goose-box -- tail -f /var/log/squid/access.json

# 遮断された通信のみを一覧表示
audit-denied:
	multipass exec goose-box -- bash -c "cat /var/log/squid/access.json | jq -r 'select(.squid_status | test(\"DENIED\")) | [.time, .method, .domain, .url] | @tsv'"

# ドメイン別アクセス頻度トップ10
audit-summary:
	multipass exec goose-box -- bash -c "cat /var/log/squid/access.json | jq -r '.domain' | sort | uniq -c | sort -rn | head -10"

# 監査ダッシュボードの URL を表示
monitor:
	@echo "=== 監査ダッシュボード ==="
	@echo "ブラウザで http://$$(multipass info goose-box | grep IPv4 | awk '{print $$2}'):7890 を開いてください"

# ==========================================
# クリーンアップ
# ==========================================

# ワークスペースのクリーンアップ
clean:
	git clean -fdX workspace/
