module type_pdf2d

  use lib_array, only : locate, interp2d
  use lib_random, only : random

  implicit none

  private

  integer,parameter :: sp = selected_real_kind(p=6,r=37)
  integer,parameter :: dp = selected_real_kind(p=15,r=307)

  ! We define a 2-d PDF by a set of nx x ny probabilities defined at nodes given by x(1...nx) and y(1...ny). We start by defining a binned PDF that has dimensions nx-1 x ny-1 and defines the probability in the rectangles defined by the nodes. The value of the probability in each bin is simply the average of the four probability points defining the rectangle. Once we have this, we compute the CDF along the x-direction (this also has shape nx-1 x ny-1). We then use the total probabilities in the x-direction to define a PDF in the y direction with ny-1 elements (pdfy). We construct the corresponding CDF (cdfy) and sample a y bin from this. We then sample the x bin from the 2-d CDF along the slice defined by the y bin. Finally, we sample from the function:
  !
  ! z = b1 + b2 * x + b3 * y + b4 * x * y
  !
  ! which is defined by the bilinear interpolation of the four points.
  !
  ! TODO: support for log sampling?

  !!@FOR real(sp):sp real(dp):dp

  public :: pdf2d_<T>
  type pdf2d_<T>
     integer :: nx, ny
     @T,allocatable :: x(:), y(:)
     @T,allocatable :: prob(:,:)
     @T,allocatable :: pdf(:,:)
     @T,allocatable :: cdf(:,:)
     @T,allocatable :: cdfy(:)
     @T,allocatable :: pdfy(:)
     logical :: normalized = .false.
  end type pdf2d_<T>

  !!@END FOR

  public :: set_pdf2d
  interface set_pdf2d
     module procedure set_pdf2d_sp
     module procedure set_pdf2d_dp
  end interface set_pdf2d

  public :: sample_pdf2d
  interface sample_pdf2d
     module procedure sample_pdf2d_sp
     module procedure sample_pdf2d_dp
  end interface sample_pdf2d

  public :: interpolate_pdf2d
  interface interpolate_pdf2d
     module procedure interpolate_pdf2d_sp
     module procedure interpolate_pdf2d_dp
  end interface interpolate_pdf2d

contains

  !!@FOR real(sp):sp real(dp):dp

  type(pdf2d_<T>) function set_pdf2d_<T>(x, y, prob) result(p)

    ! Initialize a 2-d PDF object
    !
    ! Parameters
    ! ----------
    ! x : 1-d array (size nx)
    !     The x values at which the probabilites are defined
    ! y : 1-d array (size ny)
    !     The y values at which the probabilites are defined
    ! prob : 2-d array (size nx x ny)
    !     The probabilities defined at (x,y)
    !
    ! Returns
    ! -------
    ! p : pdf2d_<T>
    !     The 2-d PDF object

    implicit none

    @T,intent(in) :: x(:), y(:), prob(:,:)
    @T,allocatable :: area(:,:)

    @T :: norm

    integer :: i, j

    p%nx = size(x)
    p%ny = size(y)

    allocate(p%x(p%nx))
    allocate(p%y(p%ny))

    p%x = x
    p%y = y

    if(size(prob,1) /= size(x)) stop "incorrect dimensions for prob"
    if(size(prob,2) /= size(y)) stop "incorrect dimensions for prob"

    allocate(p%prob(p%nx, p%ny))

    p%prob = prob

    ! Compute area of each rectangle
    allocate(area(p%nx-1, p%ny-1))
    do i=1,p%nx - 1
       do j=1,p%ny - 1
          area(i, j) = (x(i+1) - x(i)) * (y(j+1) - y(j))
       end do
    end do

    ! Compute binned PDF as average of four neighboring points times area of rectangle

    allocate(p%pdf(p%nx-1,p%ny-1))

    p%pdf = (prob(1:p%nx-1,1:p%ny-1) &
         & + prob(1:p%nx-1,2:p%ny) &
         & + prob(2:p%nx,1:p%ny-1) &
         & + prob(2:p%nx,2:p%ny)) &
         & * area * 0.25_dp

    ! Find total probability
    norm = sum(p%pdf)

    ! Normalize unbinned probability
    p%prob = p%prob / norm

    ! Normalize PDF
    p%pdf  = p%pdf / norm
    p%normalized = .true.

    ! Compute 2-d CDF along x direction

    allocate(p%cdf(p%nx-1,p%ny-1))

    p%cdf(1,:) = p%pdf(1,:)
    do i=2,p%nx - 1
       p%cdf(i,:) = p%cdf(i-1,:) + p%pdf(i,:)
    end do

    ! Find PDF and CDF in y direction
    allocate(p%pdfy(p%ny-1))
    allocate(p%cdfy(p%ny-1))
    p%pdfy = p%cdf(p%nx-1,:)
    p%cdfy(1) = p%pdfy(1)
    do j=2,p%ny - 1
       p%cdfy(j) = p%cdfy(j-1) + p%pdfy(j)
    end do
    p%cdfy = p%cdfy / p%cdfy(p%ny-1)

    ! Normalize 2-d CDF (has to be done after calculating the y-axis PDF/CDF)
    do i=1,p%nx - 1
       p%cdf(i,:) = p%cdf(i,:) / p%cdf(p%nx-1,:)
    end do

  end function set_pdf2d_<T>

  subroutine sample_pdf2d_<T>(p, x, y, xi_alt)

    ! Sample a 2-d PDF
    !
    ! Parameters
    ! ----------
    ! p : pdf2d_<T>
    !     The 2-d PDF object to sample from
    ! xi_alt : @T array with 4 elements, optional
    !     Random numbers to use for the sampling
    !
    ! Returns
    ! -------
    ! x, y : @T
    !     The x- and y-position sampled

    implicit none

    type(pdf2d_<T>), intent(in) :: p
    @T,intent(out) :: x, y
    @T,intent(in),optional :: xi_alt(4)
    @T :: xi(4)
    integer :: xbin, ybin
    @T :: b1, b2, b3, b4
    @T :: a, b, c, delta
    integer :: i

    ! Sample random numbers if not specified

    if(present(xi_alt)) then
       xi = xi_alt
    else
       do i=1,4
          call random(xi(i))
       end do
    end if

    ! Find y bin
    if(xi(1) < p%cdfy(1)) then
       ybin = 1
    else
       ybin = locate(p%cdfy, xi(1)) + 1
    end if

    ! Find x bin
    if(xi(2) < p%cdf(1, ybin)) then
       xbin = 1
    else
       xbin = locate(p%cdf(:,ybin), xi(2)) + 1
    end if

    ! Now sample the position within the rectangle. We first find the normalized position in the range [0:1,0:1]. We do this by sampling from a function given by the plane:
    !
    ! z = b1 + b2 * x + b3 * y + b4 * x * y
    !
    ! which is the bilinear interpolation of the points. The coefficients are given by:

    b1 = p%prob(xbin, ybin)
    b2 = p%prob(xbin + 1, ybin) - b1
    b3 = p%prob(xbin, ybin + 1) - b1
    b4 = p%prob(xbin + 1, ybin + 1) - b2 - b3 - b1
    !
    !    print *,'-----'
    !    print *,p%prob(xbin, ybin)
    !    print *,p%prob(xbin+1, ybin)
    !    print *,p%prob(xbin, ybin+1)
    !    print *,p%prob(xbin+1, ybin+1)
    !    print *,b1,b2,b3,b4

    ! We now construct the cumulative PDF in the y direction, and sample from that. The solution is a second-order polynomial with coefficients:

    a = 0.5_<T> * (b3 + 0.5_<T> * b4)
    b = (b1 + 0.5_<T> * b2)
    c = - xi(3) * (a + b)
    delta = sqrt(b * b - 4._<T> * a * c)

    ! We have to choose the solution in the range [0:1]

    if (a < 0) then
       if (b > delta) then
          y = (-b + delta) / a * 0.5
       else
          y = (-b - delta) / a * 0.5
       end if
    else if (a > 0) then
       if (-b < delta) then
          y = (-b + delta) / a * 0.5
       else
          y = (-b - delta) / a * 0.5
       end if
    else  ! a == 0 so not a quadratic
       y = - c / b
    end if

    !     print *,a,b,c,y

    ! Now that we have y, we can sample x, and the solution is also a polynomial with coefficients

    a = 0.5_<T> * (b2 + b4 * y)
    b = b1 + b3 * y
    c = - xi(4) * (a + b)
    delta = sqrt(b * b - 4._<T> * a * c)

    ! We have to choose the solution in the range [0:1]

    if (a < 0) then
       if (b > delta) then
          x = (-b + delta) / a * 0.5
       else
          x = (-b - delta) / a * 0.5
       end if
    else if (a > 0) then
       if (-b < delta) then
          x = (-b + delta) / a * 0.5
       else
          x = (-b - delta) / a * 0.5
       end if
    else  ! a == 0 so not a quadratic
       x = - c / b
    end if

    ! x and y are in relative units - now scale to correct positions
    x = x * (p%x(xbin+1) - p%x(xbin)) + p%x(xbin)
    y = y * (p%y(ybin+1) - p%y(ybin)) + p%y(ybin)

  end subroutine sample_pdf2d_<T>

  @T function interpolate_pdf2d_<T>(p, x, y, bounds_error, fill_value) result(prob)

    ! Interpolate a 2-d PDF
    !
    ! Parameters
    ! ----------
    ! p : pdf2d_<T>
    !     The PDF to interpolate
    ! x, y : @T
    !     Position at which to interpolate the 2-d PDF
    ! bounds_error : logical, optional
    !     Whether to raise an error if the interpolation is out of bounds
    ! fill_value : @T
    !     The value to use for out-of-bounds interpolation if bounds_error = .false.
    !
    ! Returns
    ! -------
    ! prob : @T
    !     The probability at the position requested

    implicit none
    type(pdf2d_<T>),intent(in) :: p
    @T,intent(in) :: x, y
    logical,intent(in),optional :: bounds_error
    real(<T>),intent(in),optional :: fill_value
    if(.not.p%normalized) stop "[interpolate_pdf] PDF is not normalized"
    prob = interp2d(p%x, p%y, p%prob, x, y, bounds_error, fill_value)
  end function interpolate_pdf2d_<T>

  !!@END FOR

end module type_pdf2d
