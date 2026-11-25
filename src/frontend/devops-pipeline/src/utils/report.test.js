import { normalizeInternalReportUrl } from '@/utils/report'

describe('normalizeInternalReportUrl', () => {
    it('strips the hardcoded localhost origin from INTERNAL reports', () => {
        expect(normalizeInternalReportUrl(
            'http://localhost:8080/artifactory/api-html/user/reports/demotest/pipeline/build/task/build-report.txt',
            'INTERNAL'
        )).toBe('/artifactory/api-html/user/reports/demotest/pipeline/build/task/build-report.txt')
    })

    it('strips other absolute origins from INTERNAL reports', () => {
        expect(normalizeInternalReportUrl(
            'https://ci.example.com/artifactory/api-html/user/reports/p/b/t/report.html',
            'INTERNAL'
        )).toBe('/artifactory/api-html/user/reports/p/b/t/report.html')
    })

    it('preserves query string and hash', () => {
        expect(normalizeInternalReportUrl(
            'http://localhost:8080/report/index.html?a=1#top',
            'INTERNAL'
        )).toBe('/report/index.html?a=1#top')
    })

    it('keeps THIRDPARTY report URLs absolute', () => {
        const url = 'https://third.example.com/report/index.html'
        expect(normalizeInternalReportUrl(url, 'THIRDPARTY')).toBe(url)
    })

    it('keeps already relative URLs unchanged', () => {
        const url = '/artifactory/api-html/user/reports/p/b/t/report.html'
        expect(normalizeInternalReportUrl(url, 'INTERNAL')).toBe(url)
    })

    it('handles missing values', () => {
        expect(normalizeInternalReportUrl(undefined, 'INTERNAL')).toBeUndefined()
        expect(normalizeInternalReportUrl('', 'INTERNAL')).toBe('')
    })
})
