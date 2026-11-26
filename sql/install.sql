-- Oprettes også automatisk, når ressourcen starter.
CREATE TABLE IF NOT EXISTS `m1_counterfeit_objects` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `kind`       VARCHAR(10) NOT NULL,
    `type`       VARCHAR(32) NOT NULL,
    `owner`      VARCHAR(60) NOT NULL,
    `bucket`     INT NOT NULL DEFAULT 0,
    `x`          DOUBLE NOT NULL,
    `y`          DOUBLE NOT NULL,
    `z`          DOUBLE NOT NULL,
    `h`          FLOAT  NOT NULL DEFAULT 0,
    `data`       LONGTEXT NULL,
    `created_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Register over serienumre (bruges af politiets UV-scanner)
CREATE TABLE IF NOT EXISTS `m1_counterfeit_serials` (
    `serial`     VARCHAR(16) NOT NULL,
    `counter_id` INT NOT NULL,
    `owner`      VARCHAR(60) NOT NULL,
    `amount`     INT NOT NULL DEFAULT 0,
    `x`          DOUBLE NOT NULL,
    `y`          DOUBLE NOT NULL,
    `z`          DOUBLE NOT NULL,
    `created_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`serial`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Materialer til spillere, der loggede ud midt i arbejdet (udbetales ved næste login)
CREATE TABLE IF NOT EXISTS `m1_counterfeit_refunds` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `items`      LONGTEXT NOT NULL,
    `created_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
