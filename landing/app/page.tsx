const githubUrl = "https://github.com/eastLight210/SSD_Remover";
// Always resolves to the newest published release asset.
const downloadUrl = `${githubUrl}/releases/latest/download/SSD_Remover.zip`;

function ArrowIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" width="18" height="18">
      <path d="M4 10h11M11 6l4 4-4 4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" width="18" height="18">
      <path d="M10 3v10M6 9l4 4 4-4M4 16h12" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" />
    </svg>
  );
}

function GithubIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width="18" height="18">
      <path fill="currentColor" d="M12 2C6.48 2 2 6.58 2 12.23c0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.49 0-.24-.01-1.05-.01-1.9-2.78.62-3.37-1.2-3.37-1.2-.45-1.18-1.11-1.49-1.11-1.49-.91-.64.07-.62.07-.62 1 .07 1.53 1.06 1.53 1.06.9 1.56 2.35 1.11 2.92.85.09-.66.35-1.11.64-1.37-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.35 9.35 0 0 1 12 6.96c.85 0 1.71.12 2.51.34 1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.05.36.32.68.95.68 1.92 0 1.38-.01 2.49-.01 2.83 0 .27.18.59.69.49A10.24 10.24 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z" />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width="22" height="22">
      <path d="M12 3 5.5 5.7v5.1c0 4.5 2.7 8 6.5 9.7 3.8-1.7 6.5-5.2 6.5-9.7V5.7L12 3Z" fill="none" stroke="currentColor" strokeLinejoin="round" strokeWidth="1.7" />
      <path d="m9.2 11.9 1.8 1.8 3.9-4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.7" />
    </svg>
  );
}

export default function Home() {
  return (
    <main>
      <nav className="nav-shell" aria-label="Primary navigation">
        <a className="brand" href="#top" aria-label="SSD Remover home">
          <span className="brand-mark" aria-hidden="true">
            <span />
          </span>
          <span>SSD Remover</span>
        </a>
        <div className="nav-links">
          <a href="#demo">Demo</a>
          <a href="#how-it-works">How it works</a>
          <a href="#privacy">Privacy</a>
        </div>
        <a className="nav-github" href={githubUrl} target="_blank" rel="noreferrer">
          <GithubIcon />
          <span>GitHub</span>
        </a>
      </nav>

      <section className="hero section" id="top">
        <div className="ambient ambient-one" aria-hidden="true" />
        <div className="ambient ambient-two" aria-hidden="true" />
        <p className="eyebrow"><span /> Free download · macOS 14+</p>
        <h1>Find what&apos;s holding your drive.<br /><span>Eject it safely.</span></h1>
        <p className="hero-copy">
          SSD Remover reveals the apps, background processes, and locked files blocking your external drive—then lets you close only what you choose.
        </p>
        <div className="hero-actions">
          <a className="button button-primary" href={downloadUrl}>
            <DownloadIcon /> Download for macOS
          </a>
          <a className="button button-secondary" href={githubUrl} target="_blank" rel="noreferrer">
            <GithubIcon /> View source
          </a>
        </div>
        <ul className="trust-list" aria-label="Product highlights">
          <li>macOS 14+</li>
          <li>Notarized by Apple</li>
          <li>Open source</li>
          <li>Runs locally</li>
        </ul>

        <div className="demo-wrap" id="demo">
          <div className="demo-glow" aria-hidden="true" />
          <figure className="demo-window">
            <figcaption className="window-bar">
              <span className="traffic-lights" aria-hidden="true"><i /><i /><i /></span>
              <span className="window-title">Real eject flow</span>
              <span className="recording"><i /> Recorded on macOS</span>
            </figcaption>
            <div className="demo-media">
              {/* The recording is the primary product proof on this page. */}
              <video
                autoPlay
                muted
                loop
                playsInline
                preload="auto"
                poster="/ssd-remover-demo-poster.jpg"
                aria-label="SSD Remover finding a process that blocks an external drive, terminating the selected process, and ejecting the drive successfully"
              >
                <source src="/ssd-remover-demo.webm" type="video/webm" />
                <source src="/ssd-remover-demo.mp4" type="video/mp4" />
              </video>
            </div>
          </figure>
        </div>
      </section>

      <section className="workflow section" id="how-it-works">
        <div className="section-heading">
          <p className="eyebrow"><span /> From blocked to safely ejected</p>
          <h2>Know what&apos;s in the way.<br />Stay in control.</h2>
          <p>SSD Remover turns a vague “disk in use” alert into a short, reviewable sequence.</p>
        </div>
        <div className="steps-grid">
          <article className="step-card">
            <span className="step-number">01</span>
            <div className="step-visual process-list" aria-hidden="true">
              <i /><span className="process-line wide" /><span className="process-line" />
              <i /><span className="process-line medium" /><span className="process-line short" />
              <i className="active" /><span className="process-line wide active" /><span className="process-line short" />
            </div>
            <h3>Detect the blocker</h3>
            <p>See the exact app or background process that is still using your drive.</p>
          </article>
          <article className="step-card featured">
            <span className="step-number">02</span>
            <div className="step-visual locked-file" aria-hidden="true">
              <span className="file-icon">MOV</span>
              <span><strong>Final_Cut_Pro</strong><small>/Volumes/Archive/edit.mov</small></span>
              <i>Selected</i>
            </div>
            <h3>Choose what to close</h3>
            <p>Review locked files and terminate only the processes you explicitly select.</p>
          </article>
          <article className="step-card">
            <span className="step-number">03</span>
            <div className="step-visual eject-success" aria-hidden="true">
              <span><ShieldIcon /></span>
              <strong>Drive ejected</strong>
              <small>Safe to disconnect</small>
            </div>
            <h3>Eject cleanly</h3>
            <p>SSD Remover retries the physical disk eject and confirms when it is safe to unplug.</p>
          </article>
        </div>
      </section>

      <section className="privacy section" id="privacy">
        <div className="privacy-panel">
          <div className="privacy-copy">
            <p className="eyebrow"><span /> Built to be careful</p>
            <h2>Your files stay<br />on your Mac.</h2>
            <p>Process and file-path inspection happens locally. SSD Remover does not upload, index, or analyze the contents of your drives.</p>
            <a className="text-link" href={githubUrl} target="_blank" rel="noreferrer">Inspect the source <ArrowIcon /></a>
          </div>
          <div className="privacy-cards">
            <article><span><ShieldIcon /></span><div><h3>Local by default</h3><p>No account or network connection is required to inspect blockers.</p></div></article>
            <article><span className="control-icon" aria-hidden="true">✓</span><div><h3>Explicit control</h3><p>You review the process and locked file before anything is terminated.</p></div></article>
            <article><span className="code-icon" aria-hidden="true">&lt;/&gt;</span><div><h3>Open source</h3><p>The process detection and eject flow are available to audit on GitHub.</p></div></article>
          </div>
        </div>
      </section>

      <section className="join section" id="updates">
        <div className="join-grid">
          <div className="join-copy">
            <p className="eyebrow"><span /> Automatic updates</p>
            <h2>Install once.<br />It keeps itself current.</h2>
            <p>SSD Remover checks for new versions once a day and installs them in place. No sign-up or mailing list—choose Check for Updates… in the app menu anytime.</p>
          </div>
          <div className="join-actions">
            <a className="button button-primary" href={downloadUrl}>
              <DownloadIcon /> Download for macOS
            </a>
            <p><ShieldIcon /><span>Every update is notarized by Apple and verified against the app&apos;s signing key before it installs.</span></p>
          </div>
        </div>
      </section>

      <footer>
        <a className="brand" href="#top"><span className="brand-mark" aria-hidden="true"><span /></span><span>SSD Remover</span></a>
        <p>Make “disk in use” actionable.</p>
        <div><a href={downloadUrl}>Download</a><a href={githubUrl} target="_blank" rel="noreferrer">GitHub</a><a href="#privacy">Privacy</a></div>
      </footer>
    </main>
  );
}
