# 同期フロー (Sync Flow)

`sync.sh` による配布ファイルの同期プロセスを図解します。

## 全体アーキテクチャ

```mermaid
graph TD
    subgraph Upstream [ozzy-labs/commons]
        Dist[dist/ 共有ファイル]
        SyncScript[sync.sh]
    end

    subgraph Target [Consumer Repository]
        LocalFiles[ターゲットファイル]
        Metadata[.commons/sync.yaml]
    end

    SyncScript -- 1. 比較 --> LocalFiles
    SyncScript -- 2. メタデータ参照 --> Metadata
    SyncScript -- 3. 差分適用 --> LocalFiles
    SyncScript -- 4. 更新 --> Metadata
```

## 同期ロジック詳細

```mermaid
flowchart TD
    Start([sync.sh 実行]) --> Loop[各 dist/ ファイルを走査]
    Loop --> IsPinned{Pin されている?}
    IsPinned -- Yes --> Skip[スキップ]
    IsPinned -- No --> Exists{ターゲットに存在?}
    
    Exists -- No --> Copy[新規コピー]
    Exists -- Yes --> HasDiff{内容に差分あり?}
    
    HasDiff -- No --> Unchanged[変更なしとして記録]
    HasDiff -- Yes --> SyncMode{同期モード?}
    
    SyncMode -- "-y / --yes" --> AutoSync[自動同期/マージ]
    SyncMode -- "対話モード" --> Prompt[プロンプト表示]
    
    AutoSync --> IsSurgical{構造化ファイル or マーカーあり?}
    IsSurgical -- Yes --> Merge[外科的マージ/セクションマージ]
    IsSurgical -- No --> Overwrite[全上書き]
    
    Prompt --> UserChoice{ユーザーの選択}
    UserChoice -- y --> Overwrite
    UserChoice -- m --> Merge
    UserChoice -- pin --> PinFile[Metadata に追加]
    UserChoice -- N --> Skip
    
    Overwrite --> Next
    Merge --> Next
    PinFile --> Next
    Skip --> Next
    Unchanged --> Next
    Copy --> Next
    
    Next --> EndLoop{全ファイル完了?}
    EndLoop -- No --> Loop
    EndLoop -- Yes --> WriteMeta[メタデータ更新]
    WriteMeta --> Done([完了])
```

## マージ方式の使い分け

| 方式 | 対象 | 特徴 |
|---|---|---|
| **全上書き (Copy)** | すべてのファイル | 常に `dist/` の内容で完全に置き換える（デフォルト） |
| **外科的マージ (Surgical)** | JSON, YAML | `yq` を使用。`dist/` のキーで上書きしつつ、個別キーは維持する |
| **セクションマージ (Marker)** | すべて（特に MD, YAML） | `<!-- begin: ... -->` 内のコンテンツのみを置換。外側は維持する |
