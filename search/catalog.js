(() => {
    const WASM_INDEX = "../wasm/v1/index.json";
    const PACKAGES_URL = "../Packages";
    const yearEl = document.getElementById("year");
    if (yearEl) yearEl.textContent = String(new Date().getFullYear());

    const form = document.getElementById("search-form");
    const input = document.getElementById("q");
    const statusEl = document.getElementById("status");
    const resultsEl = document.getElementById("results");
    const channelInputs = [...document.querySelectorAll('input[name="channel"]')];
    const wasiInputs = [...document.querySelectorAll('input[name="wasi"]')];
    const kindInputs = [...document.querySelectorAll('input[name="kind"]')];
    const sortInputs = [...document.querySelectorAll('input[name="sort"]')];

    let packages = [];
    let resolvedMaintainers = {};
    let roster = {};
    let lastListSig = "";

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

    const pkgKey = (pkg) =>
        pkg.channel === "deb"
            ? `deb:${pkg.name}:${pkg.architecture || ""}`
            : `wasm:${pkg.name}`;

    const blobUrl = (pkg) => {
        if (pkg.channel === "deb") {
            const file = pkg.filename || "";
            if (!file) return "";
            if (/^https?:\/\//i.test(file)) return file;
            return `../${file.replace(/^\//, "")}`;
        }
        if (!pkg.url) return "";
        if (/^https?:\/\//i.test(pkg.url)) return pkg.url;
        return `../wasm/v1/${pkg.url.replace(/^\//, "")}`;
    };

    const handlesFor = (pkg) => {
        if (Array.isArray(pkg.maintainers) && pkg.maintainers.length) return pkg.maintainers;
        const email = pkg.maintainer_email;
        if (!email) return [];
        return Object.entries(roster)
            .filter(([, rec]) => rec && rec.email === email)
            .map(([handle]) => handle);
    };

    const parsePackages = (text) => {
        const stanzas = text.trim().split(/\n\s*\n/).filter(Boolean);
        return stanzas.map((stanza) => {
            const fields = {};
            let key;
            for (const line of stanza.split("\n")) {
                if (line.startsWith(" ") && key) {
                    fields[key] += ` ${line.trim()}`;
                } else if (line.includes(":")) {
                    const i = line.indexOf(":");
                    key = line.slice(0, i);
                    fields[key] = line.slice(i + 1).trim();
                }
            }
            const maint = fields.Maintainer || "";
            const match = maint.match(/^(.*) <([^>]+)>$/);
            return {
                channel: "deb",
                name: fields.Package,
                version: fields.Version,
                architecture: fields.Architecture,
                summary: (fields.Description || "").split("\n")[0],
                long_description: fields.Description || "",
                filename: fields.Filename,
                size: fields.Size,
                digest: fields.SHA256 ? `sha256:${fields.SHA256}` : "",
                homepage: fields.Homepage || "https://repo.wawona.io/",
                maintainer_line: maint,
                maintainer_email: match ? match[2] : "",
                maintainer_name: match ? match[1] : maint,
                section: fields.Section || "",
                raw: fields,
            };
        });
    };

    const groupByKey = (rows) => {
        const map = new Map();
        for (const pkg of rows) {
            const key = pkgKey(pkg);
            const list = map.get(key) || [];
            list.push(pkg);
            map.set(key, list);
        }
        return [...map.entries()].map(([key, versions]) => {
            versions.sort((a, b) => compareVersions(b.version, a.version));
            return { key, name: versions[0].name, latest: versions[0], versions };
        });
    };

    const haystack = (pkg) =>
        [
            pkg.channel,
            pkg.name,
            pkg.summary,
            pkg.long_description,
            pkg.license,
            pkg.wasi,
            pkg.kind,
            pkg.runtime,
            pkg.architecture,
            pkg.filename,
            pkg.section,
            ...(pkg.programs || []),
            pkg.digest,
            pkg.maintainer_name,
            pkg.maintainer_email,
            ...(handlesFor(pkg) || []),
            ...(handlesFor(pkg) || []).map((h) => (resolvedMaintainers[h] || {}).name || ""),
        ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase();

    const normalizeShow = (show, channel) => {
        if (!show) return "";
        if (show.includes(":")) return show;
        if (channel === "wasm" || channel === "deb") return `${channel}:${show}`;
        return show;
    };

    const isOpen = (state, pkg) => {
        const key = pkgKey(pkg);
        if (state.show === key) return true;
        if (!state.show) return false;
        if (!state.show.includes(":")) return state.show === pkg.name;
        if (state.show === `wasm:${pkg.name}` && pkg.channel === "wasm") return true;
        if (state.show === `deb:${pkg.name}` && pkg.channel === "deb") return true;
        return false;
    };

    const readState = () => {
        const params = new URLSearchParams(window.location.search);
        const channel = params.get("channel") || "";
        return {
            query: params.get("query") || params.get("q") || "",
            show: normalizeShow(params.get("show") || "", channel),
            channel,
            wasi: params.get("wasi") || "",
            kind: params.get("kind") || "",
            sort: params.get("sort") || "relevance",
        };
    };

    const writeState = (state, replace) => {
        const params = new URLSearchParams();
        if (state.query) params.set("query", state.query);
        if (state.channel) params.set("channel", state.channel);
        if (state.show) params.set("show", state.show);
        if (state.channel !== "deb") {
            if (state.wasi) params.set("wasi", state.wasi);
            if (state.kind) params.set("kind", state.kind);
        }
        if (state.sort && state.sort !== "relevance") params.set("sort", state.sort);
        const next = params.toString() ? `?${params.toString()}` : "./";
        const url = new URL(next, window.location.href);
        if (replace) history.replaceState(state, "", url);
        else history.pushState(state, "", url);
    };

    const applyControls = (state) => {
        input.value = state.query;
        document.body.dataset.channel = state.channel || "all";
        for (const el of channelInputs) el.checked = el.value === state.channel;
        if (![...channelInputs].some((el) => el.checked)) channelInputs[0].checked = true;
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
        channel: (channelInputs.find((el) => el.checked) || {}).value || "",
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
        let groups = groupByKey(packages).filter((group) => {
            const pkg = group.latest;
            if (state.channel && pkg.channel !== state.channel) return false;
            if (state.wasi && pkg.channel === "wasm" && String(pkg.wasi || "").toLowerCase() !== state.wasi) {
                return false;
            }
            if (state.kind && pkg.channel === "wasm" && packageKind(pkg) !== state.kind) return false;
            if (q && !group.versions.some((row) => haystack(row).includes(q))) return false;
            return true;
        });
        if (state.sort === "name") {
            groups.sort((a, b) => a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
        } else if (state.sort === "version") {
            groups.sort((a, b) => compareVersions(b.latest.version, a.latest.version) || a.name.localeCompare(b.name));
        } else {
            groups.sort((a, b) => score(b, q) - score(a, q) || a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
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

    const renderMaintainers = (pkg) => {
        const handles = handlesFor(pkg);
        if (handles.length) {
            return handles
                .map((handle) => {
                    const info = resolvedMaintainers[handle] || {};
                    const name = info.name || handle;
                    const url = info.html_url || `https://github.com/${handle}`;
                    const avatar = info.avatar_url
                        ? `<img src="${escapeHtml(info.avatar_url)}" alt="" width="22" height="22">`
                        : "";
                    return `<a class="who" href="${escapeHtml(url)}" rel="noopener">${avatar}<span>${escapeHtml(name)}</span> <code>@${escapeHtml(handle)}</code></a>`;
                })
                .join(" ");
        }
        if (pkg.maintainer_line) return escapeHtml(pkg.maintainer_line);
        return "";
    };

    const wasmBody = (group, pkg, q) => {
        const programs = (pkg.programs || []).map((p) => `<code>${escapeHtml(p)}</code>`).join(" ");
        const platforms = Array.isArray(pkg.platforms) ? pkg.platforms.join(", ") : "";
        const homepage = pkg.homepage
            ? `<a href="${escapeHtml(pkg.homepage)}" rel="noopener">homepage</a>`
            : "";
        const source = pkg.source
            ? `<a href="${escapeHtml(pkg.source)}" rel="noopener">source</a>`
            : "";
        const blob = blobUrl(pkg);
        const versions = group.versions.map((v) => `<code>${escapeHtml(v.version)}</code>`).join(" ");
        const install = `wpm install ${pkg.name}`;
        const run = `wasm ${pkg.name}`;
        const kind = packageKind(pkg);
        return `
    ${pkg.long_description ? `<p class="long-desc">${highlight(pkg.long_description, q)}</p>` : ""}
    <div class="install-row">
      <div class="cmd"><code>${escapeHtml(install)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(install)}">Copy</button></div>
      <div class="cmd"><code>${escapeHtml(run)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(run)}">Copy</button></div>
    </div>
    <table class="meta">
      ${metaRow("Channel", "<code>wasm</code>")}
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
      ${metaRow("Maintainers", renderMaintainers(pkg))}
      ${metaRow("Links", [homepage, source].filter(Boolean).join(" · "))}
      ${metaRow("Digest", `<span class="digest mono">${escapeHtml(pkg.digest || "")}</span>`)}
      ${metaRow("Blob", blob ? `<a href="${escapeHtml(blob)}">${escapeHtml(pkg.url)}</a>` : "")}
    </table>
    <details class="raw-json">
      <summary>Raw index entry</summary>
      <pre>${escapeHtml(JSON.stringify(group.versions, null, 2))}</pre>
    </details>`;
    };

    const debBody = (group, pkg, q) => {
        const blob = blobUrl(pkg);
        const versions = group.versions.map((v) => `<code>${escapeHtml(v.version)}</code>`).join(" ");
        const source = "https://repo.wawona.io/";
        const apt = `apt install ${pkg.name}`;
        return `
    ${pkg.long_description && pkg.long_description !== pkg.summary ? `<p class="long-desc">${highlight(pkg.long_description, q)}</p>` : ""}
    <div class="install-row">
      <div class="cmd"><code>${escapeHtml(source)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(source)}">Copy</button></div>
      <div class="cmd"><code>${escapeHtml(apt)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(apt)}">Copy</button></div>
    </div>
    <table class="meta">
      ${metaRow("Channel", "<code>deb</code>")}
      ${metaRow("Package", `<code>${escapeHtml(pkg.name)}</code>`)}
      ${metaRow("Version", versions)}
      ${metaRow("Architecture", escapeHtml(pkg.architecture || ""))}
      ${metaRow("Section", escapeHtml(pkg.section || ""))}
      ${metaRow("Size", escapeHtml(pkg.size || ""))}
      ${metaRow("Maintainers", renderMaintainers(pkg))}
      ${metaRow("Sileo source", `<a href="${escapeHtml(source)}">${escapeHtml(source)}</a>`)}
      ${metaRow("SHA256", `<span class="digest mono">${escapeHtml(pkg.digest || "")}</span>`)}
      ${metaRow("Filename", blob ? `<a href="${escapeHtml(blob)}">${escapeHtml(pkg.filename)}</a>` : escapeHtml(pkg.filename || ""))}
    </table>
    <details class="raw-json">
      <summary>Raw Packages stanza</summary>
      <pre>${escapeHtml(JSON.stringify(pkg.raw, null, 2))}</pre>
    </details>`;
    };

    const renderPackage = (group, state) => {
        const pkg = group.latest;
        const q = state.query;
        const open = isOpen(state, pkg);
        const key = pkgKey(pkg);
        const kind = pkg.channel === "wasm" ? packageKind(pkg) : pkg.architecture || "deb";
        const chips =
            pkg.channel === "wasm"
                ? `
      <span class="chip">wasm</span>
      <span class="chip">WASI ${(pkg.wasi || "?").toUpperCase()}</span>
      <span class="chip">${escapeHtml(kind)}</span>
      ${pkg.license ? `<span class="chip">${escapeHtml(pkg.license)}</span>` : ""}`
                : `
      <span class="chip">deb</span>
      <span class="chip">${escapeHtml(pkg.architecture || "deb")}</span>
      ${pkg.section ? `<span class="chip">${escapeHtml(pkg.section)}</span>` : ""}`;
        const maintChips = handlesFor(pkg)
            .map((h) => `<span class="chip">@${escapeHtml(h)}</span>`)
            .join("");
        return `
<article class="pkg${open ? " open" : ""}" id="pkg-${escapeHtml(key)}" data-key="${escapeHtml(key)}" data-name="${escapeHtml(pkg.name)}">
  <button class="pkg-head" type="button" aria-expanded="${open ? "true" : "false"}">
    <span class="pkg-name">${highlight(pkg.name, q)}</span>
    <span class="pkg-version">${escapeHtml(pkg.version)}</span>
    <p class="pkg-summary">${highlight(pkg.summary || "", q)}</p>
    <div class="chips">${chips}${maintChips}</div>
  </button>
  <div class="pkg-body">
    ${pkg.channel === "deb" ? debBody(group, pkg, q) : wasmBody(group, pkg, q)}
  </div>
</article>`;
    };

    const listSignature = (groups, state) =>
        JSON.stringify({
            keys: groups.map((g) => g.key),
            query: state.query,
            channel: state.channel,
            wasi: state.wasi,
            kind: state.kind,
            sort: state.sort,
        });

    const applyOpenOnly = (state) => {
        for (const article of resultsEl.querySelectorAll(".pkg")) {
            const key = article.getAttribute("data-key");
            const pkg = { channel: key.startsWith("deb:") ? "deb" : "wasm", name: article.getAttribute("data-name"), architecture: key.split(":")[2] };
            const open = isOpen(state, pkg) || state.show === key;
            article.classList.toggle("open", open);
            const head = article.querySelector(".pkg-head");
            if (head) head.setAttribute("aria-expanded", open ? "true" : "false");
        }
    };

    const render = (state, replaceUrl) => {
        applyControls(state);
        if (replaceUrl) writeState(state, true);
        const groups = filtered(state);
        const total = groupByKey(packages).length;
        const wasmCount = packages.filter((p) => p.channel === "wasm").length;
        const debCount = groupByKey(packages.filter((p) => p.channel === "deb")).length;
        if (!packages.length) {
            statusEl.textContent = "The catalog loaded, but it lists no packages yet.";
            resultsEl.replaceChildren();
            lastListSig = "";
            return;
        }
        if (!groups.length) {
            statusEl.textContent = `0 of ${total} packages match.`;
            resultsEl.innerHTML = `<div class="empty">No packages match those filters. Clear the search or pick All.</div>`;
            lastListSig = "";
            return;
        }
        const channelNote = state.channel
            ? ""
            : ` (${wasmCount} wasm rows, ${debCount} deb packages)`;
        statusEl.textContent = `${groups.length} of ${total} packages${state.query ? ` matching "${state.query}"` : ""}${channelNote}.`;
        const sig = listSignature(groups, state);
        if (sig === lastListSig && resultsEl.querySelector(".pkg")) {
            applyOpenOnly(state);
            return;
        }
        lastListSig = sig;
        resultsEl.innerHTML = groups.map((group) => renderPackage(group, state)).join("");
        if (state.show) {
            const el =
                document.getElementById(`pkg-${state.show}`) ||
                resultsEl.querySelector(`[data-key="${CSS.escape(state.show)}"]`);
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

    for (const el of [...channelInputs, ...wasiInputs, ...kindInputs, ...sortInputs]) {
        el.addEventListener("change", () => {
            const state = currentFilters();
            if (state.channel === "deb") {
                state.wasi = "";
                state.kind = "";
            }
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
        const key = article.getAttribute("data-key");
        const state = currentFilters();
        state.show = state.show === key ? "" : key;
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

    const peopleFrom = (body) =>
        Object.fromEntries(
            Object.entries(body || {}).filter(([key, value]) => !key.startsWith("_") && value && typeof value === "object")
        );

    const boot = async () => {
        const state = readState();
        applyControls(state);
        try {
            const [wasmRes, packagesRes, peopleRes, rosterRes] = await Promise.all([
                fetch(WASM_INDEX, { cache: "no-cache" }),
                fetch(PACKAGES_URL, { cache: "no-cache" }),
                fetch("../maintainers.resolved.json", { cache: "no-cache" }),
                fetch("../maintainers.json", { cache: "no-cache" }),
            ]);
            if (!wasmRes.ok) throw new Error(`${WASM_INDEX} HTTP ${wasmRes.status}`);
            const index = await wasmRes.json();
            const wasmPkgs = (Array.isArray(index.packages) ? index.packages : []).map((pkg) => ({
                ...pkg,
                channel: "wasm",
            }));
            let debPkgs = [];
            if (packagesRes.ok) {
                debPkgs = parsePackages(await packagesRes.text());
            }
            packages = [...wasmPkgs, ...debPkgs];
            if (peopleRes.ok) resolvedMaintainers = peopleFrom(await peopleRes.json());
            if (rosterRes.ok) roster = peopleFrom(await rosterRes.json());
            render(state, false);
        } catch (err) {
            statusEl.classList.add("error");
            statusEl.textContent = `Could not load the catalog. wpm still uses /wasm/v1/; Sileo still uses /Packages. (${err.message})`;
        }
    };

    boot();
})();
