import {Composition, Folder} from 'remotion';
import {FPS, HEIGHT, type Locale, WIDTH} from './data';
import {plan, type Variant} from './plan';
import {Clean} from './variants/Clean';
import {Showcase} from './variants/Showcase';
import {Story} from './variants/Story';
import {Calm, calmPlan} from './variants/Calm';
import {Kinetic, kineticPlan} from './variants/Kinetic';
import {motionPlan, StoryMotion} from './variants/StoryMotion';

const components: Record<Variant, React.FC<{locale: Locale}>> = {
  clean: Clean,
  showcase: Showcase,
  story: Story,
};

const names: Record<Variant, string> = {
  clean: 'A-Clean',
  showcase: 'B-Showcase',
  story: 'C-Story',
};

/** Every variant in English and Russian, at the App Store app preview size (886×1920, 30 fps). */
export const RemotionRoot = () => (
  <Folder name="AppPreview">
    {(['clean', 'showcase', 'story'] as Variant[]).flatMap((v) =>
      (['en', 'ru'] as Locale[]).map((locale) => (
        <Composition
          key={`${v}-${locale}`}
          id={`${names[v]}-${locale}`}
          component={components[v]}
          defaultProps={{locale}}
          durationInFrames={plan(v, locale).total}
          fps={FPS}
          width={WIDTH}
          height={HEIGHT}
        />
      )),
    )}
    {(['en', 'ru'] as Locale[]).map((locale) => (
      <Composition
        key={`motion-${locale}`}
        id={`D-StoryMotion-${locale}`}
        component={StoryMotion}
        defaultProps={{locale}}
        durationInFrames={motionPlan(locale).total}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
      />
    ))}
    {(['en', 'ru'] as Locale[]).map((locale) => (
      <Composition key={`kinetic-${locale}`} id={`E-Kinetic-${locale}`} component={Kinetic} defaultProps={{locale}} durationInFrames={kineticPlan(locale).total} fps={FPS} width={WIDTH} height={HEIGHT} />
    ))}
    {(['en', 'ru'] as Locale[]).map((locale) => (
      <Composition key={`calm-${locale}`} id={`F-Calm-${locale}`} component={Calm} defaultProps={{locale}} durationInFrames={calmPlan(locale).total} fps={FPS} width={WIDTH} height={HEIGHT} />
    ))}
  </Folder>
);
