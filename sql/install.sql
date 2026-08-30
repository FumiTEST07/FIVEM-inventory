-- as-evidencestash / 押収品倉庫
-- 監査ログ (アクセス履歴) テーブル
--
-- 注意: 押収品アイテムそのものはこのテーブルには保存されません。
--       アイテムは ox_inventory が自身のテーブルに永続化します。
--       このテーブルが保持するのは「誰が・いつ・どの倉庫にアクセスしたか」だけです。
--
-- config/server.lua の logging.autoCreateTable が true の場合、
-- リソース起動時に自動作成されるため、この SQL の手動実行は任意です。
-- 手動運用にする場合は autoCreateTable を false にしてから実行してください。

CREATE TABLE IF NOT EXISTS `as_evidencestash_logs` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `stash_id` VARCHAR(64) NOT NULL COMMENT 'ox_inventory 上の stash ID',
    `stash_key` VARCHAR(64) NOT NULL COMMENT 'SharedConfig.stashes のキー',
    `citizenid` VARCHAR(64) DEFAULT NULL COMMENT 'qb-core の citizenid',
    `player_name` VARCHAR(128) DEFAULT NULL,
    `identifier` VARCHAR(64) DEFAULT NULL COMMENT 'license 識別子',
    `action` VARCHAR(32) NOT NULL COMMENT 'open / close / denied',
    `detail` VARCHAR(255) DEFAULT NULL COMMENT '拒否理由など',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_stash_created` (`stash_id`, `created_at`),
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
