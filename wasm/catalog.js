(() => {
    const INDEX_URL = "v1/index.json";
    const yearEl = document.getElementById("year");
    if (yearEl) yearEl.textContent = String(new Date().getFullYear());

    const form = document.getElementById("search-form");
    const input = document.getElementById("q");
    const statusEl = document.getElementById("status");
    const resultsEl = document.getElementById("results");
    const wasiInputs = [...document.querySelectorAll('input[name="wasi"]')];
    const kindInputs = [...document.querySelectorAll('input[name="kind"]')];
    const sortInputs = [...document.querySelectorAll('input[name="sort"]')];

    let packages = [];

    const escapeHtml = (value) =>
        String(value ?? "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");

    const highlight = (text, query) => {
        const raw = String(text ?? "");
        if (!query) return escapeHtml(raw);
        const lower = raw.toLowerCase();
        const needle = query.toLowerCase();
        let out = "";
        let i = 0;
        while (i < raw.length) {
            const hit = lower.indexOf(needle, i);
            if (hit === -1) {
                out += escapeHtml(raw.slice(i));
                break;
            }
            out += escapeHtml(raw.slice(i, hit));
            out += `<mark>${escapeHtml(raw.slice(hit, hit + needle.length))}</mark>`;
            i = hit + needle.length;
        }
        return out;
    };

    const compareVersions = (a, b) => {
        const pa = String(a).split(/[.-]/);
        const pb = String(b).split(/[.-]/);
        const n = Math.max(pa.length, pb.length);
        for (let i = 0; i < n; i += 1) {
            const na = parseInt(pa[i], 10);
            const nb = parseInt(pb[i], 10);
            const va = Number.isNaN(na) ? pa[i] || "" : na;
            const vb = Number.isNaN(nb) ? pb[i] || "" : nb;
            if (va > vb) return 1;
            if (va < vb) return -1;
        }
        return 0;
    };

    const packageKind = (pkg) => {
        if (pkg.kind) return String(pkg.kind).toLowerCase();
        if (pkg.capabilities && pkg.capabilities.wayland) return "wayland";
        return "cli";
    };

    const blobUrl = (pkg) => {
        if (!pkg.url) return "";
        if (/^https?:\/\//i.test(pkg.url)) return pkg.url;
        return `v1/${pkg.url.replace(/^\//, "")}`;
    };

    const groupByName = (rows) => {
        const map = new Map();
        for (const pkg of rows) {
            const list = map.get(pkg.name) || [];
            list.push(pkg);
            map.set(pkg.name, list);
        }
        return [...map.entries()].map(([name, versions]) => {
            versions.sort((a, b) => compareVersions(b.version, a.version));
            return { name, latest: versions[0], versions };
        });
    };

    const haystack = (pkg) =>
        [
            pkg.name,
            pkg.summary,
            pkg.long_description,
            pkg.license,
            pkg.wasi,
            pkg.kind,
            pkg.runtime,
            ...(pkg.programs || []),
            pkg.digest,
        ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase();

    const readState = () => {
        const params = new URLSearchParams(window.location.search);
        return {
            query: params.get("query") || params.get("q") || "",
            show: params.get("show") || "",
            wasi: params.get("wasi") || "",
            kind: params.get("kind") || "",
            sort: params.get("sort") || "relevance",
        };
    };

    const writeState = (state, replace) => {
        const params = new URLSearchParams();
        if (state.query) params.set("query", state.query);
        if (state.show) params.set("show", state.show);
        if (state.wasi) params.set("wasi", state.wasi);
        if (state.kind) params.set("kind", state.kind);
        if (state.sort && state.sort !== "relevance") params.set("sort", state.sort);
        const next = params.toString() ? `?${params.toString()}` : "./";
        const url = new URL(next, window.location.href);
        if (replace) history.replaceState(state, "", url);
        else history.pushState(state, "", url);
    };

    const applyControls = (state) => {
        input.value = state.query;
        for (const el of wasiInputs) el.checked = el.value === state.wasi;
        if (![...wasiInputs].some((el) => el.checked)) wasiInputs[0].checked = true;
        for (const el of kindInputs) el.checked = el.value === state.kind;
        if (![...kindInputs].some((el) => el.checked)) kindInputs[0].checked = true;
        for (const el of sortInputs) el.checked = el.value === state.sort;
        if (![...sortInputs].some((el) => el.checked)) sortInputs[0].checked = true;
    };

    const currentFilters = () => ({
        query: input.value.trim(),
        show: readState().show,
        wasi: (wasiInputs.find((el) => el.checked) || {}).value || "",
        kind: (kindInputs.find((el) => el.checked) || {}).value || "",
        sort: (sortInputs.find((el) => el.checked) || {}).value || "relevance",
    });

    const score = (group, query) => {
        if (!query) return 0;
        const q = query.toLowerCase();
        let best = 0;
        for (const pkg of group.versions) {
            const name = pkg.name.toLowerCase();
            if (name === q) best = Math.max(best, 100);
            else if (name.startsWith(q)) best = Math.max(best, 80);
            else if (name.includes(q)) best = Math.max(best, 60);
            else if (haystack(pkg).includes(q)) best = Math.max(best, 30);
        }
        return best;
    };

    const filtered = (state) => {
        const q = state.query.toLowerCase();
        let groups = groupByName(packages).filter((group) => {
            const pkg = group.latest;
            if (state.wasi && String(pkg.wasi || "").toLowerCase() !== state.wasi) return false;
            if (state.kind && packageKind(pkg) !== state.kind) return false;
            if (q && !group.versions.some((row) => haystack(row).includes(q))) return false;
            return true;
        });
        if (state.sort === "name") {
            groups.sort((a, b) => a.name.localeCompare(b.name));
        } else if (state.sort === "version") {
            groups.sort((a, b) => compareVersions(b.latest.version, a.latest.version));
        } else {
            groups.sort((a, b) => score(b, q) - score(a, q) || a.name.localeCompare(b.name));
        }
        return groups;
    };

    const metaRow = (label, html) => {
        if (!html) return "";
        return `<tr><th>${escapeHtml(label)}</th><td>${html}</td></tr>`;
    };

    const capabilityBits = (caps) => {
        if (!caps || typeof caps !== "object") return "";
        const bits = [];
        bits.push(caps.wayland ? "Wayland" : "no Wayland");
        bits.push(caps.network ? "network" : "no network");
        const fs = Array.isArray(caps.filesystem) ? caps.filesystem : [];
        bits.push(fs.length ? `filesystem: ${fs.join(", ")}` : "no extra filesystem");
        return escapeHtml(bits.join(" · "));
    };

    const renderPackage = (group, state) => {
        const pkg = group.latest;
        const q = state.query;
        const open = state.show === pkg.name;
        const programs = (pkg.programs || []).map((p) => `<code>${escapeHtml(p)}</code>`).join(" ");
        const platforms = Array.isArray(pkg.platforms) ? pkg.platforms.join(", ") : "";
        const homepage = pkg.homepage
            ? `<a href="${escapeHtml(pkg.homepage)}" rel="noopener">homepage</a>`
            : "";
        const source = pkg.source
            ? `<a href="${escapeHtml(pkg.source)}" rel="noopener">source</a>`
            : "";
        const blob = blobUrl(pkg);
        const versions = group.versions
            .map((v) => `<code>${escapeHtml(v.version)}</code>`)
            .join(" ");
        const install = `wpm install ${pkg.name}`;
        const run = `wasm ${pkg.name}`;
        const kind = packageKind(pkg);

        return `
<article class="pkg${open ? " open" : ""}" id="pkg-${escapeHtml(pkg.name)}" data-name="${escapeHtml(pkg.name)}">
  <button class="pkg-head" type="button" aria-expanded="${open ? "true" : "false"}">
    <span class="pkg-name">${highlight(pkg.name, q)}</span>
    <span class="pkg-version">${escapeHtml(pkg.version)}</span>
    <p class="pkg-summary">${highlight(pkg.summary || "", q)}</p>
    <div class="chips">
      <span class="chip">WASI ${(pkg.wasi || "?").toUpperCase()}</span>
      <span class="chip">${escapeHtml(kind)}</span>
      ${pkg.license ? `<span class="chip">${escapeHtml(pkg.license)}</span>` : ""}
      ${pkg.runtime ? `<span class="chip">${escapeHtml(pkg.runtime)}</span>` : ""}
    </div>
  </button>
  <div class="pkg-body">
    ${pkg.long_description ? `<p class="long-desc">${highlight(pkg.long_description, q)}</p>` : ""}
    <div class="install-row">
      <div class="cmd"><code>${escapeHtml(install)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(install)}">Copy</button></div>
      <div class="cmd"><code>${escapeHtml(run)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(run)}">Copy</button></div>
    </div>
    <table class="meta">
      ${metaRow("Name", `<code>${escapeHtml(pkg.name)}</code>`)}
      ${metaRow("Version", versions)}
      ${metaRow("WASI", escapeHtml(pkg.wasi || ""))}
      ${metaRow("Kind", escapeHtml(kind))}
      ${metaRow("License", escapeHtml(pkg.license || ""))}
      ${metaRow("Runtime", escapeHtml(pkg.runtime || "wawona-1"))}
      ${metaRow("Entry", escapeHtml(pkg.entry || "component.wasm"))}
      ${metaRow("Programs", programs)}
      ${metaRow("Capabilities", capabilityBits(pkg.capabilities))}
      ${metaRow("Platforms", escapeHtml(platforms))}
      ${metaRow("Links", [homepage, source].filter(Boolean).join(" · "))}
      ${metaRow("Digest", `<span class="digest mono">${escapeHtml(pkg.digest || "")}</span>`)}
      ${metaRow("Blob", blob ? `<a href="${escapeHtml(blob)}">${escapeHtml(pkg.url)}</a>` : "")}
    </table>
    <details class="raw-json">
      <summary>Raw index entry</summary>
      <pre>${escapeHtml(JSON.stringify(group.versions, null, 2))}</pre>
    </details>
  </div>
</article>`;
    };

    const render = (state, replaceUrl) => {
        applyControls(state);
        if (replaceUrl) writeState(state, true);
        const groups = filtered(state);
        const total = groupByName(packages).length;
        if (!packages.length) {
            statusEl.textContent = "The catalog index loaded, but it lists no packages yet.";
            resultsEl.innerHTML = "";
            return;
        }
        if (!groups.length) {
            statusEl.textContent = `0 of ${total} packages match.`;
            resultsEl.innerHTML = `<div class="empty">No packages match those filters. Clear the search or pick All.</div>`;
            return;
        }
        statusEl.textContent = `${groups.length} of ${total} packages${state.query ? ` matching "${state.query}"` : ""}.`;
        resultsEl.innerHTML = groups.map((group) => renderPackage(group, state)).join("");
        if (state.show) {
            const el = document.getElementById(`pkg-${state.show}`);
            if (el) el.scrollIntoView({ block: "nearest" });
        }
    };

    const copyText = async (button) => {
        const text = button.getAttribute("data-copy") || "";
        try {
            await navigator.clipboard.writeText(text);
            button.textContent = "Copied";
            setTimeout(() => {
                button.textContent = "Copy";
            }, 1600);
        } catch {
            button.textContent = "Failed";
        }
    };

    form.addEventListener("submit", (event) => {
        event.preventDefault();
        const state = currentFilters();
        writeState(state, false);
        render(state, false);
    });

    let typing = null;
    input.addEventListener("input", () => {
        clearTimeout(typing);
        typing = setTimeout(() => {
            const state = currentFilters();
            render(state, true);
        }, 120);
    });

    for (const el of [...wasiInputs, ...kindInputs, ...sortInputs]) {
        el.addEventListener("change", () => {
            const state = currentFilters();
            writeState(state, true);
            render(state, false);
        });
    }

    resultsEl.addEventListener("click", (event) => {
        const copyBtn = event.target.closest(".copy-btn");
        if (copyBtn) {
            event.preventDefault();
            copyText(copyBtn);
            return;
        }
        const head = event.target.closest(".pkg-head");
        if (!head) return;
        const article = head.closest(".pkg");
        const name = article.getAttribute("data-name");
        const state = currentFilters();
        state.show = state.show === name ? "" : name;
        writeState(state, false);
        render(state, false);
    });

    document.addEventListener("keydown", (event) => {
        if (event.key === "/" && document.activeElement !== input && !event.metaKey && !event.ctrlKey) {
            event.preventDefault();
            input.focus();
            input.select();
        }
        if (event.key === "Escape" && document.activeElement === input) input.blur();
    });

    window.addEventListener("popstate", () => {
        const state = readState();
        render(state, false);
    });

    const boot = async () => {
        const state = readState();
        applyControls(state);
        try {
            const response = await fetch(INDEX_URL, { cache: "no-cache" });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const index = await response.json();
            packages = Array.isArray(index.packages) ? index.packages : [];
            render(state, false);
        } catch (err) {
            statusEl.classList.add("error");
            statusEl.textContent = `Could not load ${INDEX_URL}. The registry is up for wpm at /wasm/v1/; this page needs that index in the browser. (${err.message})`;
        }
    };

    boot();
})();
