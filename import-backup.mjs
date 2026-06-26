#!/usr/bin/env node
//
// Import tool: download a workspace backup from a remote backup-api host
// and prepare a local directory for `tool backup-restore`.
//
// Usage:
//   node import-backup.mjs --url https://host/api/backup/<workspace> --token <JWT> [--out <dir>]
//   node import-backup.mjs --url https://host/api/backup/<workspace>/index.json --token-file test_token.txt
//
// The backup-api endpoint serves:
//   GET <url>/index.json   -> { files: [{name,size}], extraBlobs, info }
//   GET <url>/<file>       -> raw file stream
// Auth is a Bearer JWT, the real workspace is taken from the token; the
// <workspace> path segment is only a label.

import { createWriteStream, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { rename, stat } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'

const RETRY_MAX = 5
const RETRY_BASE_MS = 1000

function parseArgs (argv) {
  const args = {}
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a.startsWith('--')) {
      const key = a.slice(2)
      const next = argv[i + 1]
      if (next === undefined || next.startsWith('--')) {
        args[key] = true
      } else {
        args[key] = next
        i++
      }
    }
  }
  return args
}

const DEFAULT_URL = 'https://backup.huly.app/api/backup/e531d95b-e9f2-45b1-b2a3-20c42abecc20'

function usage (msg) {
  if (msg) console.error(`Error: ${msg}\n`)
  console.error(`Usage: node import-backup.mjs --url <backup-url> (--token <JWT> | --token-file <path>) [--out <dir>]

  --url         Backup URL up to the workspace, e.g.
                https://host/api/backup/<workspace>  (trailing /index.json is stripped)
                default: ${DEFAULT_URL}
  --token       Workspace JWT (Bearer). Owner or admin token.
  --token-file  Read the JWT from a file (default: test_token.txt if present)
  --out         Output directory (default ./backups/<workspace>)
  --max-blob-size <MB>  Skip extra blobs larger than this (0 = no limit)
  --no-blobs    Do not download extra blobs at all
`)
  process.exit(msg ? 1 : 0)
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function fmtBytes (n) {
  if (n == null) return '?'
  const u = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  let v = n
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024
    i++
  }
  return `${v.toFixed(i === 0 ? 0 : 1)}${u[i]}`
}

async function fetchRetry (url, init, attempt = 1) {
  try {
    const res = await fetch(url, init)
    if (res.status >= 500 || res.status === 429) {
      throw new Error(`HTTP ${res.status}`)
    }
    return res
  } catch (err) {
    if (attempt >= RETRY_MAX) throw err
    const delay = RETRY_BASE_MS * 2 ** (attempt - 1)
    console.error(`  retry ${attempt}/${RETRY_MAX} after ${delay}ms (${err.message})`)
    await sleep(delay)
    return fetchRetry(url, init, attempt + 1)
  }
}

function bar (frac, width = 20) {
  const f = Math.max(0, Math.min(1, frac || 0))
  const filled = Math.round(f * width)
  return `[${'#'.repeat(filled)}${'-'.repeat(width - filled)}]`
}

// p: { total, done, startMs, idx, count, name, fileDone, fileTotal }
function renderProgress (p) {
  const elapsed = (Date.now() - p.startMs) / 1000
  const speed = elapsed > 0 ? p.done / elapsed : 0
  const totalFrac = p.total ? p.done / p.total : 0
  const eta = speed > 0 && p.total ? (p.total - p.done) / speed : 0
  const etaStr = p.total ? ` ETA ${Math.ceil(eta)}s` : ''
  const overall = `${bar(totalFrac)} ${(totalFrac * 100).toFixed(1)}%  ${fmtBytes(p.done)}/${fmtBytes(p.total)}  ${fmtBytes(speed)}/s${etaStr}`
  const file = `[${p.idx}/${p.count}] ${p.name}  ${fmtBytes(p.fileDone)}/${fmtBytes(p.fileTotal)}`
  process.stdout.write(`\r\x1b[2K${overall}\n\x1b[2K${file}\x1b[1A`)
}

async function downloadFile (baseUrl, token, file, outDir, prog) {
  const target = join(outDir, file.name)
  const tmp = `${target}.part`
  mkdirSync(dirname(target), { recursive: true })

  // countedForFile: bytes of THIS file already added to prog.done, so retries
  // can reconcile without double-counting against the overall total.
  let countedForFile = 0
  const setFileDone = (bytes) => {
    prog.done += bytes - countedForFile
    countedForFile = bytes
    prog.fileDone = bytes
  }

  // Skip if already fully downloaded.
  if (existsSync(target) && file.size != null) {
    const s = statSync(target)
    if (s.size === file.size) {
      setFileDone(file.size)
      renderProgress(prog)
      return s.size
    }
  }

  prog.fileTotal = file.size

  for (let attempt = 1; attempt <= RETRY_MAX; attempt++) {
    let resumeFrom = 0
    if (existsSync(tmp)) {
      try {
        resumeFrom = (await stat(tmp)).size
      } catch {}
    }

    const headers = { Authorization: `Bearer ${token}` }
    if (resumeFrom > 0) headers.Range = `bytes=${resumeFrom}-`

    try {
      const res = await fetch(encodeURI(`${baseUrl}/${file.name}`), { headers })
      if (res.status === 416) {
        // Range not satisfiable - assume complete.
        await rename(tmp, target).catch(() => {})
        setFileDone(file.size ?? resumeFrom)
        return file.size ?? resumeFrom
      }
      if (!(res.status === 200 || res.status === 206)) {
        throw new Error(`HTTP ${res.status}`)
      }
      if (res.status === 200) resumeFrom = 0 // server ignored Range

      const cl = Number(res.headers.get('content-length'))
      prog.fileTotal = file.size ?? ((resumeFrom + (Number.isFinite(cl) ? cl : 0)) || undefined)

      const out = createWriteStream(tmp, { flags: resumeFrom > 0 && res.status === 206 ? 'a' : 'w' })
      let done = resumeFrom
      setFileDone(done)
      let lastTick = 0

      const src = Readable.fromWeb(res.body)
      src.on('data', (chunk) => {
        done += chunk.length
        const now = Date.now()
        if (now - lastTick > 150) {
          setFileDone(done)
          renderProgress(prog)
          lastTick = now
        }
      })

      await pipeline(src, out)
      setFileDone(done)
      renderProgress(prog)

      await rename(tmp, target)
      return done
    } catch (err) {
      // Roll back this file's contribution so the retry recounts cleanly.
      setFileDone(0)
      if (attempt >= RETRY_MAX) {
        process.stdout.write('\n\n')
        throw new Error(`failed ${file.name}: ${err.message}`)
      }
      const delay = RETRY_BASE_MS * 2 ** (attempt - 1)
      process.stdout.write(`\n\n  retry ${file.name} ${attempt}/${RETRY_MAX} after ${delay}ms (${err.message})\n`)
      await sleep(delay)
    }
  }
  return 0
}

async function main () {
  const args = parseArgs(process.argv.slice(2))
  if (args.help || args.h) usage()

  const rawUrl = typeof args.url === 'string' ? args.url : DEFAULT_URL
  // Strip trailing /index.json and trailing slashes.
  const baseUrl = rawUrl.replace(/\/index\.(json|html)\/?$/, '').replace(/\/+$/, '')

  let token
  if (typeof args.token === 'string') {
    token = args.token.trim()
  } else {
    const tokenFile = typeof args['token-file'] === 'string' ? args['token-file'] : 'test_token.txt'
    if (existsSync(tokenFile)) {
      token = readFileSync(tokenFile, 'utf8').trim()
    } else {
      usage('--token or --token-file is required')
    }
  }

  console.log(`Fetching backup index from ${baseUrl}/index.json`)
  const idxRes = await fetchRetry(`${baseUrl}/index.json`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  if (idxRes.status !== 200) {
    throw new Error(`index.json HTTP ${idxRes.status}: ${await idxRes.text()}`)
  }
  const index = await idxRes.json()
  if (index.error) throw new Error(`backup-api error: ${index.error}`)

  const files = (index.files ?? []).filter((f) => f.name && !f.name.endsWith('.hash'))
  if (files.length === 0) throw new Error('no files in backup index')

  // Service files needed for restore. backup.json.gz is usually in files[],
  // but backup.size.gz / blob-info.json.gz often are not. Probe and add them.
  const serviceNames = ['backup.json.gz', 'backup.size.gz', 'blob-info.json.gz']
  const haveNames = new Set(files.map((f) => f.name))
  for (const name of serviceNames) {
    if (haveNames.has(name)) continue
    try {
      const head = await fetch(encodeURI(`${baseUrl}/${name}`), {
        method: 'HEAD',
        headers: { Authorization: `Bearer ${token}` }
      })
      if (head.status === 200) {
        const cl = Number(head.headers.get('content-length'))
        files.push({ name, size: Number.isFinite(cl) ? cl : undefined })
        console.log(`Added service file: ${name}`)
      }
    } catch {}
  }

  const urlWs = baseUrl.split('/').filter(Boolean).pop()
  const wsName = index.info?.workspace ?? urlWs ?? 'ws'
  const outDir = typeof args.out === 'string' ? args.out : join('backups', wsName)
  const totalSize = files.reduce((s, f) => s + (f.size ?? 0), 0)

  console.log(`Workspace: ${wsName}  version: ${index.info?.version ?? '?'}`)
  console.log(`Files: ${files.length}  total: ${fmtBytes(totalSize)}`)
  console.log(`Output: ${outDir}\n`)

  await runDownloads(files, baseUrl, token, outDir, 'backup files')

  // Extra blobs (large media not embedded in the backup tarballs). They must be
  // re-uploaded into the local datalake separately, after restore.
  const skipBlobs = args['no-blobs'] === true
  // Max blob size in MB (0 or unset = no limit). Blobs larger than this are skipped.
  const maxBlobMB = typeof args['max-blob-size'] === 'string' ? Number(args['max-blob-size']) : 0
  const maxBlobBytes = Number.isFinite(maxBlobMB) && maxBlobMB > 0 ? maxBlobMB * 1024 * 1024 : 0

  const allExtra = (index.extraBlobs ?? []).filter((b) => b.name && b.size > 0)
  const extraBlobs = maxBlobBytes > 0 ? allExtra.filter((b) => b.size <= maxBlobBytes) : allExtra
  const skipped = allExtra.length - extraBlobs.length

  if (!skipBlobs && allExtra.length > 0) {
    const blobHost = (typeof args['blob-url'] === 'string' ? args['blob-url'] : 'https://dl-eu.huly.app').replace(/\/+$/, '')
    const blobBase = `${blobHost}/blob/${urlWs}`
    const blobDir = join(outDir, 'blobs')
    const blobTotal = extraBlobs.reduce((s, b) => s + (b.size ?? 0), 0)

    console.log(`\nExtra blobs: ${extraBlobs.length}/${allExtra.length}  total: ${fmtBytes(blobTotal)}`)
    if (skipped > 0) {
      console.log(`Skipping ${skipped} blob(s) larger than ${maxBlobMB}MB.`)
    }
    console.log(`Source: ${blobBase}`)

    await runDownloads(extraBlobs, blobBase, token, blobDir, 'blobs')

    // Manifest consumed by the blob upload step (name + contentType).
    writeFileSync(
      join(blobDir, 'blobs.json'),
      JSON.stringify({ workspace: wsName, blobs: extraBlobs }, null, 2)
    )
    console.log(`Blob manifest written: ${join(blobDir, 'blobs.json')}`)
  } else if (extraBlobs.length > 0) {
    console.log(`\nSkipping ${extraBlobs.length} extra blobs (--no-blobs).`)
  }

  console.log(`\nAll done into ${outDir}`)
  console.log(`\nTo restore into the local platform run:`)
  console.log(`  ./backup-restore.sh ${outDir} <target-workspace>`)
}

async function runDownloads (files, base, token, outDir, label) {
  const total = files.reduce((s, f) => s + (f.size ?? 0), 0)
  const prog = {
    total: total || undefined,
    done: 0,
    startMs: Date.now(),
    idx: 0,
    count: files.length,
    name: '',
    fileDone: 0,
    fileTotal: 0
  }
  console.log(`Downloading ${label} -> ${outDir}`)
  for (const file of files) {
    prog.idx++
    prog.name = file.name
    prog.fileDone = 0
    prog.fileTotal = file.size
    renderProgress(prog)
    await downloadFile(base, token, file, outDir, prog)
  }
  process.stdout.write('\n\n')
  console.log(`Downloaded ${fmtBytes(prog.done)} (${label}).`)
}

main().catch((err) => {
  console.error(`\nFATAL: ${err.message}`)
  process.exit(1)
})
