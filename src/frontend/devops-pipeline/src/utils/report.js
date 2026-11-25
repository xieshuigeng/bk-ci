/*
 * Internal report URLs are generated from the CI server's inner API host,
 * which can be `http://localhost:8080` in a local deployment. Using that URL
 * directly in the browser breaks when the UI is opened from another machine.
 *
 * The reports API already strips the origin for internal reports; apply the
 * same normalization to pipeline outputs so reports open through the current
 * site origin. Third-party reports keep their absolute URLs.
 */
export function normalizeInternalReportUrl (url, reportType) {
    if (!url) return url
    if (reportType !== 'INTERNAL') return url

    try {
        const base = typeof window === 'undefined' ? 'http://localhost' : window.location.origin
        const parsed = new URL(url, base)
        return `${parsed.pathname}${parsed.search}${parsed.hash}`
    } catch (e) {
        return url
    }
}
