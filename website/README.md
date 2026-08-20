# 剪金 JianJin 官网

项目介绍站，用 [Blume](https://useblume.dev) 构建，部署在 GitHub Pages：

<https://hungtcs.github.io/JianJin/>

## 本地开发

需要 Node.js 22.12 或更高（CI 上用 26）与 pnpm。

```bash
pnpm install
pnpm dev        # 开发服务器，热重载
pnpm build      # 静态产物输出到 dist/
pnpm preview    # 按静态托管的方式预览上一次构建
pnpm validate   # 校验站内链接与锚点
```

## 结构

```
blume.config.ts   站点配置：标题、主题、GitHub 链接、Pages 的 site + base
docs/             全部内容（MDX），文件即路由
public/logo.svg   页眉的图标（Blume 会把它内联进 DOM）
icon.svg          自动识别为 favicon，内容同上，只有深色模式的写法不同
```

## Logo

两个文件都来自 `jianjin-logo-icon.svg`（200×200 的图标版）。**没有用那版带
「剪金 JIANJIN」字样的 full lockup**：Blume 的页眉把图标固定渲染成 20px 高
（`h-5`），640×200 的横版缩到 20px 后「剪金」两个字只有 7px 高，糊成一团。
字样交给 Blume 自己的 `logo.text` 渲染——它用主题的字体与前景色，深浅两种模式
都自动正确。

原图有一处在深色模式下会出问题，已就地补上：图标那块 `#1E1B18` 的底占了整个
标记 **87%** 的面积，而深色模式的页面背景是 `oklch(0.085)`，两者对比度只有
**1.19:1**——整个圆角方块的轮廓会消失，只剩下占 4% 面积的金色元素浮在那里。

修法是**不动任何原有颜色**，只加一个 `.jj-ring` 空心矩形，在深色模式下描一道
`#8A7A63` 的细边（对页面背景约 5:1，20px 下正好 1px），把轮廓找回来。浅色模式
下 `stroke: none`，与原图一字不差。

两个文件的差别只在触发方式：`public/logo.svg` 被内联进页面，用
`[data-theme="dark"]`（Blume 总会把解析后的模式写在 `<html>` 上）；`icon.svg`
作为 favicon 独立渲染，没有页面上下文，用 `@media (prefers-color-scheme: dark)`。

主题的强调色 `accent` 也取自 logo 那道金色渐变的两端：浅色模式 `#B8791C`，
深色模式 `#E8B23A`。

## 两件容易踩的事

**`deployment.base` 不能少。** GitHub Pages 的项目站点服务在 `/<仓库名>/` 之下，
`blume.config.ts` 里的 `site` 只给出 origin，子路径要靠 `base: "/JianJin"`。
两者都对，站内链接、资源、sitemap 才会带上 `/JianJin` 前缀。

**首页截图引用的是仓库根的 `docs/images/screenshot.png`，不在这里复制一份。**
相对路径的图片会被 Astro 在构建时优化（734 kB PNG → 184 kB WebP，并写入宽高避免
布局抖动），dev 与 build 都实测可用。复制一份的代价是换图要记得改两处——而漏掉的
那一处不会报错，只会悄悄过期。

因此 `.github/workflows/pages.yml` 的 `paths` 过滤器除了 `website/**` 还必须包含
`docs/images/**`，否则只换截图不会触发部署。

代价是 `pnpm validate` 会对它报一条 `BLUME_BROKEN_ASSET` 警告，**是误报**：校验器
只在 `public/` 里找资源，不认识构建期优化的相对路径图片。产物里的 `<img>` 指向真实
存在的 `_astro/*.webp`，构建是绿的；把图挪走再构建会直接失败，这条依赖是真的。
