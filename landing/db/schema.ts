import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const betaSignups = sqliteTable("beta_signups", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  email: text("email").notNull().unique(),
  useCase: text("use_case").notNull(),
  source: text("source").notNull().default("landing"),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
});
