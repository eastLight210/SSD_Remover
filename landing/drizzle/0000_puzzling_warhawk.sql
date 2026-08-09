CREATE TABLE `beta_signups` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`email` text NOT NULL,
	`use_case` text NOT NULL,
	`source` text DEFAULT 'landing' NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `beta_signups_email_unique` ON `beta_signups` (`email`);