import { defineConfig } from "blume";

export default defineConfig({
  title: "剪金 JianJin",
  description:
    "从视频里快速挑选出有用的片段并无损导出的桌面应用。键盘打点，-c copy 零重编码。",
  logo: {
    image: "/logo.svg",
    text: "剪金 JianJin",
  },

  // 站点只有中文一种语言。列出单个 locale 是为了让 Blume 用中文的界面文案
  // （搜索、目录、页脚等）——zh-CN 会落到内置的 zh 语言包上。
  i18n: {
    defaultLocale: "zh-CN",
    locales: [{ code: "zh-CN", label: "简体中文" }],
  },

  // 头部仓库链接与每页的「在 GitHub 上编辑」都由这里驱动。
  github: {
    owner: "hungtcs",
    repo: "JianJin",
    branch: "master",
    dir: "website",
  },

  theme: {
    // 取自 logo 里那道金色渐变的两端：浅色模式用深的一端才压得住白底，
    // 深色模式用亮的一端。两个模式各取一头，比一个颜色硬撑两边稳。
    accent: { light: "#B8791C", dark: "#E8B23A" },
    radius: "md",
    mode: "system",
  },

  // GitHub Pages 的项目站点服务于 /<仓库名>/ 之下，两者都要给：
  // site 提供绝对 origin（sitemap / canonical / OG 图），base 提供子路径。
  deployment: {
    output: "static",
    site: "https://hungtcs.github.io",
    base: "/JianJin",
  },
});
