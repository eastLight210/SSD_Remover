"use client";

import { FormEvent, useState } from "react";

type FormStatus = "idle" | "submitting" | "success" | "error";

export function BetaSignupForm() {
  const [status, setStatus] = useState<FormStatus>("idle");
  const [message, setMessage] = useState("We’ll only email about SSD Remover beta access.");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("submitting");
    setMessage("Saving your beta request…");

    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/beta", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          email: form.get("email"),
          useCase: form.get("useCase"),
          company: form.get("company"),
        }),
      });
      const payload = (await response.json()) as { message?: string };
      if (!response.ok) throw new Error(payload.message || "Could not save your request.");
      setStatus("success");
      setMessage(payload.message || "You’re on the private beta list.");
      event.currentTarget.reset();
    } catch (error) {
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "Could not save your request. Please try again.");
    }
  }

  return (
    <form className="beta-form" onSubmit={handleSubmit} data-status={status}>
      <div className="field-group">
        <label htmlFor="email">Email address</label>
        <input id="email" name="email" type="email" autoComplete="email" placeholder="you@example.com" required disabled={status === "submitting"} />
      </div>
      <div className="field-group">
        <label htmlFor="useCase">What do you use external drives for?</label>
        <select id="useCase" name="useCase" defaultValue="" required disabled={status === "submitting"}>
          <option value="" disabled>Select one</option>
          <option value="backups">Backups</option>
          <option value="photo-video">Photo or video work</option>
          <option value="development">Development</option>
          <option value="general-storage">General storage</option>
          <option value="other">Something else</option>
        </select>
      </div>
      <div className="honeypot" aria-hidden="true">
        <label htmlFor="company">Company</label>
        <input id="company" name="company" type="text" tabIndex={-1} autoComplete="off" />
      </div>
      <button className="button button-primary submit-button" type="submit" disabled={status === "submitting"}>
        {status === "submitting" ? "Joining…" : "Join the private beta"}
        <span aria-hidden="true">→</span>
      </button>
      <p className="form-message" aria-live="polite"><span aria-hidden="true" />{message}</p>
    </form>
  );
}
