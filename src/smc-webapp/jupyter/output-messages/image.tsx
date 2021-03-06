import { delay } from "awaiting";
import { React, Component, Rendered } from "smc-webapp/app-framework";
import { get_blob_url } from "../server-urls";

interface ImageProps {
  type: string;
  sha1?: string; // one of sha1 or value must be given
  value?: string;
  project_id?: string;
  width?: number;
  height?: number;
}

interface ImageState {
  attempts: number;
}

export class Image extends Component<ImageProps, ImageState> {
  private is_mounted: any;

  constructor(props: ImageProps, context: any) {
    super(props, context);
    this.state = { attempts: 0 };
  }

  load_error = async (): Promise<void> => {
    if (this.state.attempts < 5 && this.is_mounted) {
      await delay(500);
      if (!this.is_mounted) return;
      this.setState({ attempts: this.state.attempts + 1 });
    }
  };

  componentDidMount(): void {
    this.is_mounted = true;
  }

  componentWillUnmount(): void {
    this.is_mounted = false;
  }

  extension = (): string => {
    return this.props.type.split("/")[1].split("+")[0];
  };

  render_using_server(project_id: string, sha1: string): Rendered {
    const src =
      get_blob_url(project_id, this.extension(), sha1) +
      `&attempts=${this.state.attempts}`;
    return (
      <img
        src={src}
        onError={this.load_error}
        width={this.props.width}
        height={this.props.height}
      />
    );
  }

  encoding = (): string => {
    switch (this.props.type) {
      case "image/svg+xml":
        return "utf8";
      default:
        return "base64";
    }
  };

  render_locally(value: string): Rendered {
    // The encodeURIComponent is definitely necessary these days.
    // See https://github.com/sagemathinc/cocalc/issues/3197 and the comments at
    // https://css-tricks.com/probably-dont-base64-svg/
    const src = `data:${
      this.props.type
    };${this.encoding()},${encodeURIComponent(value)}`;
    return (
      <img src={src} width={this.props.width} height={this.props.height} />
    );
  }

  render(): Rendered {
    if (this.props.value != null) {
      return this.render_locally(this.props.value);
    } else if (this.props.sha1 != null && this.props.project_id != null) {
      return this.render_using_server(this.props.project_id, this.props.sha1);
    } else {
      // not enough info to render
      return <span>[unavailable {this.extension()} image]</span>;
    }
  }
}
