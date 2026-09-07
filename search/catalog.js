(() => {
    const WASM_INDEX = "../wasm/v1/index.json";
    const PACKAGES_URL = "../Packages";
    const yearEl = document.getElementById("year");
    if (yearEl) yearEl.textContent = String(new Date().getFullYear());

    const form = document.getElementById("search-form");
    const input = document.getElementById("q");
    const channelHidden = document.getElementById("channel-hidden");
    const statusEl = document.getElementById("status");
    const resultsEl = document.getElementById("results");
    const chooserEl = document.getElementById("chooser");
    const catalogMain = document.getElementById("catalog-main");
    const doorWasm = document.getElementById("door-wasm");
    const doorDeb = document.getElementById("door-deb");
    const pageTitle = document.getElementById("page-title");
    const ledeEl = document.getElementById("lede");
    const kickerEl = document.getElementById("kicker");
    const laneBanner = document.getElementById("lane-banner");
    const filterNote = document.getElementById("filter-note");
    const navChoose = document.getElementById("nav-choose");
    const navWasm = document.getElementById("nav-wasm");
    const navDeb = document.getElementById("nav-deb");
    const channelInputs = [...document.querySelectorAll('aside input[name="channel"]')];
    const wasiInputs = [...document.querySelectorAll('input[name="wasi"]')];
    const kindInputs = [...document.querySelectorAll('input[name="kind"]')];
    const sortInputs = [...document.querySelectorAll('input[name="sort"]')];
    const filtersEl = document.querySelector(".filters");

    let packages = [];
    let loadedLane = "";
    let resolvedMaintainers = {};
    let roster = {};
    let lastListSig = "";
    let loadToken = 0;

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

    const namedInputs = (name) => [...document.querySelectorAll(`input[name="${name}"]`)];

    const ARCH_LABELS = {
        "iphoneos-arm64": "iphoneos-arm64 · iOS Sileo rootless",
        "iphoneos-arm": "iphoneos-arm · iOS Sileo rootful",
        "iphoneos-arm64e": "iphoneos-arm64e · iOS RootHide",
        aarch64: "aarch64 · Termux Android sideload",
        arm: "arm · Termux Android sideload",
    };

    const isIosJailbreakArch = (arch) => String(arch || "").startsWith("iphoneos-");

    const fillChoices = (hostId, inputName, values, selected, labels) => {
        const host = document.getElementById(hostId);
        if (!host) return;
        const unique = [...new Set(values.filter(Boolean))].sort((a, b) => a.localeCompare(b));
        const allChecked = !selected ? " checked" : "";
        const options = unique
            .map((value) => {
                const checked = selected === value ? " checked" : "";
                const label = (labels && labels[value]) || value;
                return `<label><input type="radio" name="${inputName}" value="${escapeHtml(value)}"${checked}> ${escapeHtml(label)}</label>`;
            })
            .join("");
        host.innerHTML = `<label><input type="radio" name="${inputName}" value=""${allChecked}> All</label>${options}`;
    };

    const fillDebFilters = (selectedArch, selectedSection) => {
        const archs = packages.filter((pkg) => pkg.channel === "deb").map((pkg) => pkg.architecture);
        const sections = packages.filter((pkg) => pkg.channel === "deb").map((pkg) => pkg.section);
        fillChoices("arch-options", "arch", archs, selectedArch, ARCH_LABELS);
        fillChoices("section-options", "section", sections, selectedSection);
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

    const laneOf = (channel) => (channel === "wasm" || channel === "deb" ? channel : "");

    const readState = () => {
        const params = new URLSearchParams(window.location.search);
        const channel = laneOf(params.get("channel") || "");
        return {
            query: params.get("query") || params.get("q") || "",
            show: normalizeShow(params.get("show") || "", channel),
            channel,
            wasi: params.get("wasi") || "",
            kind: params.get("kind") || "",
            arch: params.get("arch") || "",
            section: params.get("section") || "",
            sort: params.get("sort") || "relevance",
        };
    };

    const writeState = (state, replace) => {
        const params = new URLSearchParams();
        if (state.channel) params.set("channel", state.channel);
        if (state.query) params.set("query", state.query);
        if (state.show) params.set("show", state.show);
        if (state.channel === "wasm") {
            if (state.wasi) params.set("wasi", state.wasi);
            if (state.kind) params.set("kind", state.kind);
        }
        if (state.channel === "deb") {
            if (state.arch) params.set("arch", state.arch);
            if (state.section) params.set("section", state.section);
        }
        if (state.sort && state.sort !== "relevance") params.set("sort", state.sort);
        const next = params.toString() ? `?${params.toString()}` : "./";
        const url = new URL(next, window.location.href);
        if (replace) history.replaceState(state, "", url);
        else history.pushState(state, "", url);
    };

    const doorHref = (channel, query) => {
        const params = new URLSearchParams();
        params.set("channel", channel);
        if (query) params.set("query", query);
        return `./?${params.toString()}`;
    };

    const syncChooserLinks = (query) => {
        if (doorWasm) doorWasm.href = doorHref("wasm", query);
        if (doorDeb) doorDeb.href = doorHref("deb", query);
    };

    const applyLaneCopy = (channel) => {
        if (navChoose) navChoose.removeAttribute("aria-current");
        if (navWasm) navWasm.removeAttribute("aria-current");
        if (navDeb) navDeb.removeAttribute("aria-current");
        if (!channel) {
            document.title = "Choose a Wawona package catalog";
            if (kickerEl) kickerEl.textContent = "repo.wawona.io/search";
            if (pageTitle) pageTitle.textContent = "Two catalogs. Pick one.";
            if (ledeEl) {
                ledeEl.textContent =
                    "App Store / Play wasm is not the same product as APT debs. Debs split: Sileo on jailbroken iOS (rootless and rootful), Termux on sideloaded Android (not jailbreak, not Play). They do not share an index with wasm. Choose a catalog before you search.";
            }
            if (laneBanner) {
                laneBanner.hidden = true;
                laneBanner.textContent = "";
            }
            if (filterNote) filterNote.textContent = "";
            input.placeholder = "Type a name, then pick a catalog";
            if (channelHidden) channelHidden.value = "";
            if (navChoose) navChoose.setAttribute("aria-current", "page");
            return;
        }
        if (channelHidden) channelHidden.value = channel;
        if (channel === "wasm") {
            document.title = "Mode A wasm packages (App Store / Play)";
            if (kickerEl) kickerEl.textContent = "Mode A · store-safe";
            if (pageTitle) pageTitle.textContent = "Wasm packages for wpm";
            if (ledeEl) {
                ledeEl.innerHTML =
                    "App Store and Play compliance: WASI bytecode only. Install with <code>wpm</code>. Machine API: <a href=\"../wasm/v1/index.json\"><code>/wasm/v1</code></a>. Sileo and Termux debs are a different catalog.";
            }
            if (laneBanner) {
                laneBanner.hidden = false;
                laneBanner.className = "lane-banner lane-a";
                laneBanner.textContent =
                    "Store-safe WASI bytecode. App Store and Play binaries must never read APT, /Packages, or .deb.";
            }
            if (filterNote) {
                filterNote.innerHTML = "Install: <code>wpm install &lt;name&gt;</code>. Not Sileo. Not Termux. Not <code>/Packages</code>.";
            }
            input.placeholder = "Search wasm packages";
            if (navWasm) navWasm.setAttribute("aria-current", "page");
            return;
        }
        document.title = "Sileo iOS and Termux Android debs";
        if (kickerEl) kickerEl.textContent = "APT debs";
        if (pageTitle) pageTitle.textContent = "Sileo and Termux deb packages";
        if (ledeEl) {
            ledeEl.innerHTML =
                "Same APT source <code>https://repo.wawona.io/</code>. <strong>Sileo</strong> is jailbroken iOS (rootless and rootful). <strong>Termux</strong> is sideloaded Android only (not jailbreak, not Play). Store <code>wpm</code> never sees this list.";
        }
        if (laneBanner) {
            laneBanner.hidden = false;
            laneBanner.className = "lane-banner lane-b";
            laneBanner.textContent =
                "Filter architecture: iphoneos-* is Sileo iOS jailbreak. aarch64 is Termux Android sideload, not jailbreak. Never in App Store or Play.";
        }
        if (filterNote) {
            filterNote.innerHTML =
                "Sileo: add <code>https://repo.wawona.io/</code> then install. Termux: same URL in sideloaded Android <code>apt</code>. Not <code>wpm</code>.";
        }
        input.placeholder = "Search Sileo or Termux debs";
        if (navDeb) navDeb.setAttribute("aria-current", "page");
    };

    const applyControls = (state) => {
        input.value = state.query;
        document.body.dataset.channel = state.channel || "choose";
        applyLaneCopy(state.channel);
        syncChooserLinks(state.query);
        const choosing = !state.channel;
        if (chooserEl) chooserEl.hidden = !choosing;
        if (catalogMain) catalogMain.hidden = choosing;
        for (const el of channelInputs) el.checked = el.value === state.channel;
        for (const el of wasiInputs) el.checked = el.value === state.wasi;
        if (![...wasiInputs].some((el) => el.checked) && wasiInputs[0]) wasiInputs[0].checked = true;
        for (const el of kindInputs) el.checked = el.value === state.kind;
        if (![...kindInputs].some((el) => el.checked) && kindInputs[0]) kindInputs[0].checked = true;
        if (state.channel === "deb") fillDebFilters(state.arch, state.section);
        for (const el of namedInputs("arch")) el.checked = el.value === state.arch;
        if (![...namedInputs("arch")].some((el) => el.checked) && namedInputs("arch")[0]) {
            namedInputs("arch")[0].checked = true;
        }
        for (const el of namedInputs("section")) el.checked = el.value === state.section;
        if (![...namedInputs("section")].some((el) => el.checked) && namedInputs("section")[0]) {
            namedInputs("section")[0].checked = true;
        }
        for (const el of sortInputs) el.checked = el.value === state.sort;
        if (![...sortInputs].some((el) => el.checked) && sortInputs[0]) sortInputs[0].checked = true;
    };

    const currentFilters = () => {
        const live = readState();
        return {
            query: input.value.trim(),
            show: live.show,
            channel: live.channel || (channelInputs.find((el) => el.checked) || {}).value || "",
            wasi: (wasiInputs.find((el) => el.checked) || {}).value || "",
            kind: (kindInputs.find((el) => el.checked) || {}).value || "",
            arch: (namedInputs("arch").find((el) => el.checked) || {}).value || "",
            section: (namedInputs("section").find((el) => el.checked) || {}).value || "",
            sort: (sortInputs.find((el) => el.checked) || {}).value || "relevance",
        };
    };

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
            if (state.arch && pkg.channel === "deb" && pkg.architecture !== state.arch) return false;
            if (state.section && pkg.channel === "deb" && pkg.section !== state.section) return false;
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

    const packageLink = (pkg) => {
        const params = new URLSearchParams();
        params.set("channel", pkg.channel);
        params.set("show", pkgKey(pkg));
        return `https://repo.wawona.io/search/?${params.toString()}`;
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
        const link = packageLink(pkg);
        return `
    ${pkg.long_description ? `<p class="long-desc">${highlight(pkg.long_description, q)}</p>` : ""}
    <div class="install-row">
      <div class="cmd"><code>${escapeHtml(install)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(install)}">Copy</button></div>
      <div class="cmd"><code>${escapeHtml(run)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(run)}">Copy</button></div>
      <div class="cmd"><code>permalink</code><button type="button" class="copy-btn" data-copy="${escapeHtml(link)}">Copy link</button></div>
    </div>
    <table class="meta">
      ${metaRow("Catalog", "<code>Mode A wasm</code> (App Store / Play, <code>wpm</code>)")}
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
        const link = packageLink(pkg);
        return `
    ${pkg.long_description && pkg.long_description !== pkg.summary ? `<p class="long-desc">${highlight(pkg.long_description, q)}</p>` : ""}
    <div class="install-row">
      <div class="cmd"><code>${escapeHtml(source)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(source)}">Copy</button></div>
      <div class="cmd"><code>${escapeHtml(apt)}</code><button type="button" class="copy-btn" data-copy="${escapeHtml(apt)}">Copy</button></div>
      <div class="cmd"><code>permalink</code><button type="button" class="copy-btn" data-copy="${escapeHtml(link)}">Copy link</button></div>
    </div>
    <table class="meta">
      ${metaRow("Catalog", isIosJailbreakArch(pkg.architecture)
          ? "<code>deb</code> (Sileo iOS jailbreak, rootless/rootful. Not Termux. Not App Store.)"
          : "<code>deb</code> (Termux Android sideload. Not jailbreak. Not Play.)")}
      ${metaRow("Package", `<code>${escapeHtml(pkg.name)}</code>`)}
      ${metaRow("Version", versions)}
      ${metaRow("Architecture", escapeHtml(ARCH_LABELS[pkg.architecture] || pkg.architecture || ""))}
      ${metaRow("Section", escapeHtml(pkg.section || ""))}
      ${metaRow("Size", escapeHtml(pkg.size || ""))}
      ${metaRow("Maintainers", renderMaintainers(pkg))}
      ${metaRow(isIosJailbreakArch(pkg.architecture) ? "Sileo source" : "Termux apt source", `<a href="${escapeHtml(source)}">${escapeHtml(source)}</a>`)}
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
      <span class="chip chip-mode-a">Mode A · store-safe</span>
      <span class="chip">wasm</span>
      <span class="chip">WASI ${(pkg.wasi || "?").toUpperCase()}</span>
      <span class="chip">${escapeHtml(kind)}</span>
      ${pkg.license ? `<span class="chip">${escapeHtml(pkg.license)}</span>` : ""}`
                : `
      <span class="chip chip-mode-b">${isIosJailbreakArch(pkg.architecture) ? "Sileo · iOS jailbreak" : "Termux · Android sideload"}</span>
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
            arch: state.arch,
            section: state.section,
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
        if (!state.channel) {
            packages = [];
            loadedLane = "";
            lastListSig = "";
            if (statusEl) statusEl.textContent = "Pick a catalog. Wasm and APT debs are never listed together.";
            if (resultsEl) resultsEl.replaceChildren();
            return;
        }
        const groups = filtered(state);
        const total = groupByKey(packages).length;
        if (!packages.length) {
            statusEl.textContent = "This catalog loaded, but it lists no packages yet.";
            resultsEl.replaceChildren();
            lastListSig = "";
            return;
        }
        if (!groups.length) {
            statusEl.textContent = `0 of ${total} packages match.`;
            resultsEl.innerHTML = `<div class="empty">No packages match those filters in this catalog.</div>`;
            lastListSig = "";
            return;
        }
        const lane = state.channel === "wasm" ? "Mode A wasm" : "APT debs";
        statusEl.textContent = `${groups.length} of ${total} ${lane}${state.query ? ` matching "${state.query}"` : ""}.`;
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
        if (!state.channel) {
            syncChooserLinks(state.query);
            writeState({ ...state, channel: "" }, false);
            render(state, false);
            return;
        }
        writeState(state, false);
        render(state, false);
    });

    let typing = null;
    input.addEventListener("input", () => {
        clearTimeout(typing);
        typing = setTimeout(() => {
            const state = currentFilters();
            if (!state.channel) {
                syncChooserLinks(state.query);
                writeState({ ...state, channel: "" }, true);
                return;
            }
            render(state, true);
        }, 120);
    });

    const goLane = async (state) => {
        writeState(state, true);
        try {
            await ensureLane(state.channel);
            statusEl.classList.remove("error");
            render(state, false);
        } catch (err) {
            statusEl.classList.add("error");
            statusEl.textContent = `Could not load this catalog. (${err.message})`;
            resultsEl.replaceChildren();
        }
    };

    for (const el of channelInputs) {
        el.addEventListener("change", () => {
            const state = currentFilters();
            state.channel = el.value;
            if (state.channel === "deb") {
                state.wasi = "";
                state.kind = "";
            } else {
                state.arch = "";
                state.section = "";
            }
            state.show = "";
            goLane(state);
        });
    }

    for (const el of [...wasiInputs, ...kindInputs, ...sortInputs]) {
        el.addEventListener("change", () => {
            const state = currentFilters();
            writeState(state, true);
            render(state, false);
        });
    }

    if (filtersEl) {
        filtersEl.addEventListener("change", (event) => {
            const target = event.target;
            if (!(target instanceof HTMLInputElement)) return;
            if (target.name !== "arch" && target.name !== "section") return;
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
        goLane(readState());
    });

    const peopleFrom = (body) =>
        Object.fromEntries(
            Object.entries(body || {}).filter(([key, value]) => !key.startsWith("_") && value && typeof value === "object")
        );

    const loadPeople = async () => {
        if (Object.keys(resolvedMaintainers).length && Object.keys(roster).length) return;
        const [peopleRes, rosterRes] = await Promise.all([
            fetch("../maintainers.resolved.json", { cache: "no-cache" }),
            fetch("../maintainers.json", { cache: "no-cache" }),
        ]);
        if (peopleRes.ok) resolvedMaintainers = peopleFrom(await peopleRes.json());
        if (rosterRes.ok) roster = peopleFrom(await rosterRes.json());
    };

    const ensureLane = async (channel) => {
        const lane = laneOf(channel);
        if (!lane) {
            packages = [];
            loadedLane = "";
            return;
        }
        if (loadedLane === lane && packages.length) return;
        const token = (loadToken += 1);
        await loadPeople();
        if (lane === "wasm") {
            const wasmRes = await fetch(WASM_INDEX, { cache: "no-cache" });
            if (!wasmRes.ok) throw new Error(`${WASM_INDEX} HTTP ${wasmRes.status}`);
            const index = await wasmRes.json();
            if (token !== loadToken) return;
            packages = (Array.isArray(index.packages) ? index.packages : []).map((pkg) => ({
                ...pkg,
                channel: "wasm",
            }));
        } else {
            const packagesRes = await fetch(PACKAGES_URL, { cache: "no-cache" });
            if (!packagesRes.ok) throw new Error(`${PACKAGES_URL} HTTP ${packagesRes.status}`);
            if (token !== loadToken) return;
            packages = parsePackages(await packagesRes.text());
        }
        loadedLane = lane;
        lastListSig = "";
    };

    const boot = async () => {
        const state = readState();
        applyControls(state);
        if (!state.channel) {
            render(state, false);
            return;
        }
        try {
            await ensureLane(state.channel);
            render(state, false);
        } catch (err) {
            statusEl.classList.add("error");
            statusEl.textContent =
                state.channel === "wasm"
                    ? `Could not load /wasm/v1. wpm still uses that API. (${err.message})`
                    : `Could not load /Packages. Sileo still uses the APT source. (${err.message})`;
        }
    };

    boot();
})();
